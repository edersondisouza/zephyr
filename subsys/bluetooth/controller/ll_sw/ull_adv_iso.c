/*
 * Copyright (c) 2021 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr.h>
#include <soc.h>
#include <sys/byteorder.h>
#include <bluetooth/bluetooth.h>

#include "hal/cpu.h"
#include "hal/ccm.h"
#include "hal/ticker.h"

#include "util/util.h"
#include "util/mem.h"
#include "util/memq.h"
#include "util/mfifo.h"
#include "util/mayfly.h"

#include "ticker/ticker.h"

#include "pdu.h"

#include "lll.h"
#include "lll/lll_vendor.h"
#include "lll/lll_adv_types.h"
#include "lll_adv.h"
#include "lll/lll_adv_pdu.h"
#include "lll_conn.h"
#include "lll_adv_iso.h"

#include "ull_internal.h"
#include "ull_adv_types.h"
#include "ull_adv_internal.h"
#include "ull_chan_internal.h"

#include "ll.h"
#include "ll_feat.h"

#define BT_DBG_ENABLED IS_ENABLED(CONFIG_BT_DEBUG_HCI_DRIVER)
#define LOG_MODULE_NAME bt_ctlr_ull_adv_iso
#include "common/log.h"
#include "hal/debug.h"

static uint32_t ull_adv_iso_start(struct ll_adv_iso_set *adv_iso,
				  uint32_t ticks_anchor,
				  uint32_t iso_interval_us);
static void mfy_iso_offset_get(void *param);
static inline struct pdu_big_info *big_info_get(struct pdu_adv *pdu);
static inline void big_info_offset_fill(struct pdu_big_info *bi,
					uint32_t ticks_offset,
					uint32_t start_us);
static int init_reset(void);
static inline struct ll_adv_iso_set *ull_adv_iso_get(uint8_t handle);
static void ticker_cb(uint32_t ticks_at_expire, uint32_t ticks_drift,
		      uint32_t remainder, uint16_t lazy, uint8_t force,
		      void *param);
static void ticker_op_cb(uint32_t status, void *param);
static void ticker_stop_op_cb(uint32_t status, void *param);
static void adv_iso_disable(void *param);
static void disabled_cb(void *param);
static void tx_lll_flush(void *param);

static memq_link_t link_lll_prepare;
static struct mayfly mfy_lll_prepare = {0U, 0U, &link_lll_prepare, NULL, NULL};

static struct ll_adv_iso_set ll_adv_iso[BT_CTLR_ADV_SET];

uint8_t ll_big_create(uint8_t big_handle, uint8_t adv_handle, uint8_t num_bis,
		      uint32_t sdu_interval, uint16_t max_sdu,
		      uint16_t max_latency, uint8_t rtn, uint8_t phy,
		      uint8_t packing, uint8_t framing, uint8_t encryption,
		      uint8_t *bcode)
{
	uint8_t hdr_data[1 + sizeof(uint8_t *)];
	struct lll_adv_sync *lll_adv_sync;
	struct lll_adv_iso *lll_adv_iso;
	struct ll_adv_iso_set *adv_iso;
	struct pdu_adv *pdu_prev, *pdu;
	struct pdu_big_info *big_info;
	uint8_t pdu_big_info_size;
	uint32_t ticks_anchor_iso;
	uint32_t iso_interval_us;
	memq_link_t *link_cmplt;
	memq_link_t *link_term;
	struct ll_adv_set *adv;
	uint16_t ctrl_spacing;
	uint32_t latency_pdu;
	uint8_t ter_idx;
	uint8_t *acad;
	uint32_t ret;
	uint8_t err;
	uint8_t bn;

	adv_iso = ull_adv_iso_get(big_handle);

	/* Already created */
	if (!adv_iso || adv_iso->lll.adv) {
		return BT_HCI_ERR_CMD_DISALLOWED;
	}

	/* No advertising set created */
	adv = ull_adv_is_created_get(adv_handle);
	if (!adv) {
		return BT_HCI_ERR_UNKNOWN_ADV_IDENTIFIER;
	}

	/* Does not identify a periodic advertising train or
	 * the periodic advertising trains is already associated
	 * with another BIG.
	 */
	lll_adv_sync = adv->lll.sync;
	if (!lll_adv_sync || lll_adv_sync->iso) {
		return BT_HCI_ERR_UNKNOWN_ADV_IDENTIFIER;
	}

	if (IS_ENABLED(CONFIG_BT_CTLR_PARAM_CHECK)) {
		if (num_bis == 0U || num_bis > 0x1F) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (sdu_interval < 0x000100 || sdu_interval > 0x0FFFFF) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (max_sdu < 0x0001 || max_sdu > 0x0FFF) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (max_latency > 0x0FA0) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (rtn > 0x0F) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (phy > (BT_HCI_LE_EXT_SCAN_PHY_1M |
			   BT_HCI_LE_EXT_SCAN_PHY_2M |
			   BT_HCI_LE_EXT_SCAN_PHY_CODED)) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (packing > 1U) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (framing > 1U) {
			return BT_HCI_ERR_INVALID_PARAM;
		}

		if (encryption > 1U) {
			return BT_HCI_ERR_INVALID_PARAM;
		}
	}

	/* Allocate link buffer for created event */
	link_cmplt = ll_rx_link_alloc();
	if (!link_cmplt) {
		return BT_HCI_ERR_MEM_CAPACITY_EXCEEDED;
	}

	/* Allocate link buffer for sync lost event */
	link_term = ll_rx_link_alloc();
	if (!link_term) {
		ll_rx_link_release(link_cmplt);

		return BT_HCI_ERR_MEM_CAPACITY_EXCEEDED;
	}

	/* Store parameters in LLL context */
	/* TODO: parameters to ULL if only accessed by ULL */
	lll_adv_iso = &adv_iso->lll;
	lll_adv_iso->handle = big_handle;
	lll_adv_iso->max_pdu = LL_BIS_OCTETS_TX_MAX;
	lll_adv_iso->phy = phy;
	lll_adv_iso->phy_flags = PHY_FLAGS_S8;

	/* Mandatory Num_BIS = 1 */
	lll_adv_iso->num_bis = num_bis;

	/* BN (Burst Count), Mandatory BN = 1 */
	bn = ceiling_fraction(max_sdu, lll_adv_iso->max_pdu);
	if (bn > PDU_BIG_BN_MAX) {
		/* Restrict each BIG event to maximum burst per BIG event */
		lll_adv_iso->bn = PDU_BIG_BN_MAX;

		/* Ceil the required burst count per SDU to next maximum burst
		 * per BIG event.
		 */
		bn = ceiling_fraction(bn, PDU_BIG_BN_MAX) * PDU_BIG_BN_MAX;
	} else {
		lll_adv_iso->bn = bn;
	}

	/* Immediate Repetition Count (IRC), Mandatory IRC = 1 */
	lll_adv_iso->irc = rtn + 1U;

	/* Calculate NSE (No. of Sub Events), Mandatory NSE = 1,
	 * without PTO added.
	 */
	lll_adv_iso->nse = lll_adv_iso->bn * lll_adv_iso->irc;

	/* NOTE: Calculate sub_interval, if interleaved then it is Num_BIS x
	 *       BIS_Spacing (by BT Spec.)
	 *       else if sequential, then by our implementation, lets keep it
	 *       max_tx_time for Max_PDU + tMSS.
	 */
	lll_adv_iso->sub_interval = PDU_BIS_US(lll_adv_iso->max_pdu, encryption,
					       phy, lll_adv_iso->phy_flags) +
				    EVENT_MSS_US;
	ctrl_spacing = PDU_BIS_US(sizeof(struct pdu_big_ctrl), encryption, phy,
				  lll_adv_iso->phy_flags) + EVENT_IFS_US;

	latency_pdu = max_latency * USEC_PER_MSEC * lll_adv_iso->bn / bn;

	/* Based on packing requested, sequential or interleaved */
	if (packing) {
		uint32_t latency;
		uint32_t reserve;

		lll_adv_iso->bis_spacing = lll_adv_iso->sub_interval;
		latency = lll_adv_iso->sub_interval * lll_adv_iso->nse *
			   lll_adv_iso->num_bis;
		reserve = latency + ctrl_spacing +
			  (EVENT_OVERHEAD_START_US + EVENT_OVERHEAD_END_US);
		if (reserve < latency_pdu) {
			lll_adv_iso->ptc = ((latency_pdu - reserve) /
					    (lll_adv_iso->sub_interval *
					     lll_adv_iso->bn)) *
					   lll_adv_iso->bn;
		} else {
			lll_adv_iso->ptc = 0U;
		}
		lll_adv_iso->nse += lll_adv_iso->ptc;
		lll_adv_iso->sub_interval = lll_adv_iso->bis_spacing *
					    lll_adv_iso->nse;
	} else {
		uint32_t latency;
		uint32_t reserve;

		latency = lll_adv_iso->sub_interval * lll_adv_iso->nse;
		reserve = latency + ctrl_spacing +
			  (EVENT_OVERHEAD_START_US + EVENT_OVERHEAD_END_US);
		if (reserve < latency_pdu) {
			lll_adv_iso->ptc = ((latency_pdu - reserve) /
					    (lll_adv_iso->sub_interval *
					     lll_adv_iso->bn)) *
					   lll_adv_iso->bn;
		} else {
			lll_adv_iso->ptc = 0U;
		}

		lll_adv_iso->nse += lll_adv_iso->ptc;
		lll_adv_iso->bis_spacing = lll_adv_iso->sub_interval *
					   lll_adv_iso->nse;
	}

	/* Pre-Transmission Offset (PTO) */
	if (lll_adv_iso->ptc) {
		lll_adv_iso->pto = bn / lll_adv_iso->bn;
	} else {
		lll_adv_iso->pto = 0U;
	}

	/* TODO: Group count, GC = NSE / BN; PTO = GC - IRC;
	 *       Is this required?
	 */

	lll_adv_iso->sdu_interval = sdu_interval;
	lll_adv_iso->max_sdu = max_sdu;

	util_saa_le32(lll_adv_iso->seed_access_addr, big_handle);

	lll_csrand_get(lll_adv_iso->base_crc_init,
		       sizeof(lll_adv_iso->base_crc_init));
	lll_adv_iso->data_chan_count =
		ull_chan_map_get(lll_adv_iso->data_chan_map);
	lll_adv_iso->latency_prepare = 0U;
	lll_adv_iso->latency_event = 0U;
	lll_adv_iso->term_req = 0U;
	lll_adv_iso->term_ack = 0U;
	lll_adv_iso->chm_req = 0U;
	lll_adv_iso->chm_ack = 0U;
	lll_adv_iso->ctrl_expire = 0U;

	/* TODO: framing support */
	lll_adv_iso->framing = framing;

	/* Calculate ISO interval */
	/* iso_interval shall be at least SDU interval,
	 * or integer multiple of SDU interval for unframed PDUs
	 */
	iso_interval_us = ((sdu_interval * lll_adv_iso->bn) /
			   (bn * CONN_INT_UNIT_US)) * CONN_INT_UNIT_US;

	/* Allocate next PDU */
	err = ull_adv_sync_pdu_alloc(adv, ULL_ADV_PDU_EXTRA_DATA_ALLOC_IF_EXIST, &pdu_prev, &pdu,
				     NULL, NULL, &ter_idx);
	if (err) {
		return err;
	}

	/* Add ACAD to AUX_SYNC_IND */
	if (encryption) {
		pdu_big_info_size = PDU_BIG_INFO_ENCRYPTED_SIZE;
	} else {
		pdu_big_info_size = PDU_BIG_INFO_CLEARTEXT_SIZE;
	}
	hdr_data[0] = pdu_big_info_size + PDU_ADV_DATA_HEADER_SIZE;
	err = ull_adv_sync_pdu_set_clear(lll_adv_sync, pdu_prev, pdu,
					 ULL_ADV_PDU_HDR_FIELD_ACAD, 0U,
					 &hdr_data);
	if (err) {
		ll_rx_link_release(link_cmplt);
		ll_rx_link_release(link_term);

		return err;
	}

	(void)memcpy(&acad, &hdr_data[1], sizeof(acad));
	acad[PDU_ADV_DATA_HEADER_LEN_OFFSET] =
		pdu_big_info_size + (PDU_ADV_DATA_HEADER_SIZE -
				     PDU_ADV_DATA_HEADER_LEN_SIZE);
	acad[PDU_ADV_DATA_HEADER_TYPE_OFFSET] = BT_DATA_BIG_INFO;
	big_info = (void *)&acad[PDU_ADV_DATA_HEADER_DATA_OFFSET];

	/* big_info->offset, big_info->offset_units and
	 * big_info->payload_count_framing[] will be filled by periodic
	 * advertising event.
	 */

	big_info->iso_interval =
		sys_cpu_to_le16(iso_interval_us / CONN_INT_UNIT_US);
	big_info->num_bis = lll_adv_iso->num_bis;
	big_info->nse = lll_adv_iso->nse;
	big_info->bn = lll_adv_iso->bn;
	big_info->sub_interval = sys_cpu_to_le24(lll_adv_iso->sub_interval);
	big_info->pto = lll_adv_iso->pto;
	big_info->spacing = sys_cpu_to_le24(lll_adv_iso->bis_spacing);
	big_info->irc = lll_adv_iso->irc;
	big_info->max_pdu = lll_adv_iso->max_pdu;
	(void)memcpy(&big_info->seed_access_addr, lll_adv_iso->seed_access_addr,
		     sizeof(big_info->seed_access_addr));
	big_info->sdu_interval = sys_cpu_to_le24(sdu_interval);
	big_info->max_sdu = max_sdu;
	(void)memcpy(&big_info->base_crc_init, lll_adv_iso->base_crc_init,
		     sizeof(big_info->base_crc_init));
	(void)memcpy(big_info->chm_phy, lll_adv_iso->data_chan_map,
		     sizeof(big_info->chm_phy));
	big_info->chm_phy[4] &= 0x1F;
	big_info->chm_phy[4] |= ((find_lsb_set(phy) - 1U) << 5);
	big_info->payload_count_framing[0] = lll_adv_iso->payload_count;
	big_info->payload_count_framing[1] = lll_adv_iso->payload_count >> 8;
	big_info->payload_count_framing[2] = lll_adv_iso->payload_count >> 16;
	big_info->payload_count_framing[3] = lll_adv_iso->payload_count >> 24;
	big_info->payload_count_framing[4] = lll_adv_iso->payload_count >> 32;
	big_info->payload_count_framing[4] &= ~BIT(7);
	big_info->payload_count_framing[4] |= ((framing & 0x01) << 7);

	/* Associate the ISO instance with an Extended Advertising instance */
	lll_adv_iso->adv = &adv->lll;

	/* Store the link buffer for ISO create and terminate complete event */
	adv_iso->node_rx_complete.hdr.link = link_cmplt;
	adv_iso->node_rx_terminate.hdr.link = link_term;

	/* Initialise LLL header members */
	lll_hdr_init(lll_adv_iso, adv_iso);

	/* Start sending BIS empty data packet for each BIS */
	ticks_anchor_iso = ticker_ticks_now_get();
	ret = ull_adv_iso_start(adv_iso, ticks_anchor_iso, iso_interval_us);
	if (ret) {
		/* FIXME: release resources */
		return BT_HCI_ERR_CMD_DISALLOWED;
	}

	/* Associate the ISO instance with a Periodic Advertising */
	lll_adv_sync->iso = lll_adv_iso;

	/* Commit the BIGInfo in the ACAD field of Periodic Advertising */
	lll_adv_sync_data_enqueue(lll_adv_sync, ter_idx);

	return BT_HCI_ERR_SUCCESS;
}

uint8_t ll_big_test_create(uint8_t big_handle, uint8_t adv_handle,
			   uint8_t num_bis, uint32_t sdu_interval,
			   uint16_t iso_interval, uint8_t nse, uint16_t max_sdu,
			   uint16_t max_pdu, uint8_t phy, uint8_t packing,
			   uint8_t framing, uint8_t bn, uint8_t irc,
			   uint8_t pto, uint8_t encryption, uint8_t *bcode)
{
	/* TODO: Implement */
	ARG_UNUSED(big_handle);
	ARG_UNUSED(adv_handle);
	ARG_UNUSED(num_bis);
	ARG_UNUSED(sdu_interval);
	ARG_UNUSED(iso_interval);
	ARG_UNUSED(nse);
	ARG_UNUSED(max_sdu);
	ARG_UNUSED(max_pdu);
	ARG_UNUSED(phy);
	ARG_UNUSED(packing);
	ARG_UNUSED(framing);
	ARG_UNUSED(bn);
	ARG_UNUSED(irc);
	ARG_UNUSED(pto);
	ARG_UNUSED(encryption);
	ARG_UNUSED(bcode);

	return BT_HCI_ERR_CMD_DISALLOWED;
}

uint8_t ll_big_terminate(uint8_t big_handle, uint8_t reason)
{
	struct lll_adv_sync *lll_adv_sync;
	struct lll_adv_iso *lll_adv_iso;
	struct ll_adv_iso_set *adv_iso;
	struct pdu_adv *pdu_prev, *pdu;
	struct node_rx_pdu *node_rx;
	struct lll_adv *lll_adv;
	struct ll_adv_set *adv;
	uint8_t ter_idx;
	uint8_t err;

	adv_iso = ull_adv_iso_get(big_handle);
	if (!adv_iso) {
		return BT_HCI_ERR_UNKNOWN_ADV_IDENTIFIER;
	}

	lll_adv_iso = &adv_iso->lll;
	lll_adv = lll_adv_iso->adv;
	if (!lll_adv) {
		return BT_HCI_ERR_UNKNOWN_ADV_IDENTIFIER;
	}

	if (lll_adv_iso->term_req) {
		return BT_HCI_ERR_CMD_DISALLOWED;
	}

	lll_adv_sync = lll_adv->sync;
	adv = HDR_LLL2ULL(lll_adv);

	/* Remove Periodic Advertising association */
	lll_adv_sync->iso = NULL;

	/* Allocate next PDU */
	err = ull_adv_sync_pdu_alloc(adv, ULL_ADV_PDU_EXTRA_DATA_ALLOC_IF_EXIST, &pdu_prev, &pdu,
				     NULL, NULL, &ter_idx);
	if (err) {
		return err;
	}

	/* Remove ACAD to AUX_SYNC_IND */
	err = ull_adv_sync_pdu_set_clear(lll_adv_sync, pdu_prev, pdu,
					 0U, ULL_ADV_PDU_HDR_FIELD_ACAD, NULL);
	if (err) {
		return err;
	}

	lll_adv_sync_data_enqueue(lll_adv_sync, ter_idx);

	/* Prepare BIG terminate event, will be enqueued after tx flush  */
	node_rx = (void *)&adv_iso->node_rx_terminate;
	node_rx->hdr.type = NODE_RX_TYPE_BIG_TERMINATE;
	node_rx->hdr.handle = big_handle;
	node_rx->hdr.rx_ftr.param = adv_iso;

	if (reason == BT_HCI_ERR_REMOTE_USER_TERM_CONN) {
		*((uint8_t *)node_rx->pdu) = BT_HCI_ERR_LOCALHOST_TERM_CONN;
	} else {
		*((uint8_t *)node_rx->pdu) = reason;
	}

	/* Request terminate procedure */
	lll_adv_iso->term_reason = reason;
	lll_adv_iso->term_req = 1U;

	return BT_HCI_ERR_SUCCESS;
}

int ull_adv_iso_init(void)
{
	int err;

	err = init_reset();
	if (err) {
		return err;
	}

	return 0;
}

int ull_adv_iso_reset(void)
{
	int err;

	err = init_reset();
	if (err) {
		return err;
	}

	return 0;
}

#if defined(CONFIG_BT_CTLR_HCI_ADV_HANDLE_MAPPING)
uint8_t ll_adv_iso_by_hci_handle_get(uint8_t hci_handle, uint8_t *handle)
{
	struct ll_adv_iso_set *adv_iso;
	uint8_t idx;

	adv_iso =  &ll_adv_iso[0];

	for (idx = 0U; idx < BT_CTLR_ADV_SET; idx++, adv_iso++) {
		if (adv_iso->lll.adv &&
		    (adv_iso->hci_handle == hci_handle)) {
			*handle = idx;
			return 0U;
		}
	}

	return BT_HCI_ERR_UNKNOWN_ADV_IDENTIFIER;
}

uint8_t ll_adv_iso_by_hci_handle_new(uint8_t hci_handle, uint8_t *handle)
{
	struct ll_adv_iso_set *adv_iso, *adv_iso_empty;
	uint8_t idx;

	adv_iso = &ll_adv_iso[0];
	adv_iso_empty = NULL;

	for (idx = 0U; idx < BT_CTLR_ADV_SET; idx++, adv_iso++) {
		if (adv_iso->lll.adv) {
			if (adv_iso->hci_handle == hci_handle) {
				return BT_HCI_ERR_CMD_DISALLOWED;
			}
		} else if (!adv_iso_empty) {
			adv_iso_empty = adv_iso;
			*handle = idx;
		}
	}

	if (adv_iso_empty) {
		memset(adv_iso_empty, 0U, sizeof(*adv_iso_empty));
		adv_iso_empty->hci_handle = hci_handle;
		return 0U;
	}

	return BT_HCI_ERR_MEM_CAPACITY_EXCEEDED;
}
#endif /* CONFIG_BT_CTLR_HCI_ADV_HANDLE_MAPPING */

void ull_adv_iso_offset_get(struct ll_adv_sync_set *sync)
{
	static memq_link_t link;
	static struct mayfly mfy = {0U, 0U, &link, NULL, mfy_iso_offset_get};
	uint32_t ret;

	mfy.param = sync;
	ret = mayfly_enqueue(TICKER_USER_ID_ULL_HIGH, TICKER_USER_ID_ULL_LOW, 1,
			     &mfy);
	LL_ASSERT(!ret);
}

void ull_adv_iso_done_complete(struct node_rx_event_done *done)
{
	struct ll_adv_iso_set *adv_iso;
	struct lll_adv_iso *lll;
	struct node_rx_hdr *rx;
	memq_link_t *link;

	/* switch to normal prepare */
	mfy_lll_prepare.fp = lll_adv_iso_prepare;

	/* Get reference to ULL context */
	adv_iso = CONTAINER_OF(done->param, struct ll_adv_iso_set, ull);
	lll = &adv_iso->lll;

	/* Prepare BIG complete event */
	rx = (void *)&adv_iso->node_rx_complete;
	link = rx->link;
	if (!link) {
		/* NOTE: When BIS events have overlapping prepare placed in
		 *       in the pipeline, more than one done complete event
		 *       will be generated, lets ignore the additional done
		 *       events.
		 */
		return;
	}
	rx->link = NULL;

	rx->type = NODE_RX_TYPE_BIG_COMPLETE;
	rx->handle = lll->handle;
	rx->rx_ftr.param = adv_iso;

	ll_rx_put(link, rx);
	ll_rx_sched();
}

void ull_adv_iso_done_terminate(struct node_rx_event_done *done)
{
	struct ll_adv_iso_set *adv_iso;
	struct lll_adv_iso *lll;
	uint32_t ret;

	/* Get reference to ULL context */
	adv_iso = CONTAINER_OF(done->param, struct ll_adv_iso_set, ull);
	lll = &adv_iso->lll;

	/* Skip if terminated already (we come here if pipeline being flushed */
	if (unlikely(lll->handle == LLL_ADV_HANDLE_INVALID)) {
		return;
	}

	ret = ticker_stop(TICKER_INSTANCE_ID_CTLR, TICKER_USER_ID_ULL_HIGH,
			  (TICKER_ID_ADV_ISO_BASE + lll->handle),
			  ticker_stop_op_cb, adv_iso);
	LL_ASSERT((ret == TICKER_STATUS_SUCCESS) ||
		  (ret == TICKER_STATUS_BUSY));

	/* Invalidate the handle */
	lll->handle = LLL_ADV_HANDLE_INVALID;
}

static int init_reset(void)
{
	/* Add initializations common to power up initialization and HCI reset
	 * initializations.
	 */
	return 0;
}

static inline struct ll_adv_iso_set *ull_adv_iso_get(uint8_t handle)
{
	if (handle >= CONFIG_BT_CTLR_ADV_SET) {
		return NULL;
	}

	return &ll_adv_iso[handle];
}

static uint32_t ull_adv_iso_start(struct ll_adv_iso_set *adv_iso,
				  uint32_t ticks_anchor,
				  uint32_t iso_interval_us)
{
	uint32_t ticks_slot_overhead;
	uint32_t volatile ret_cb;
	uint32_t slot_us;
	uint32_t ret;

	ull_hdr_init(&adv_iso->ull);

	/* FIXME: Calc slot_us */
	slot_us = EVENT_OVERHEAD_START_US + EVENT_OVERHEAD_END_US;
	slot_us += 1000U;

	adv_iso->ull.ticks_active_to_start = 0U;
	adv_iso->ull.ticks_prepare_to_start =
		HAL_TICKER_US_TO_TICKS(EVENT_OVERHEAD_XTAL_US);
	adv_iso->ull.ticks_preempt_to_start =
		HAL_TICKER_US_TO_TICKS(EVENT_OVERHEAD_PREEMPT_MIN_US);
	adv_iso->ull.ticks_slot = HAL_TICKER_US_TO_TICKS(slot_us);

	if (IS_ENABLED(CONFIG_BT_CTLR_LOW_LAT)) {
		ticks_slot_overhead = MAX(adv_iso->ull.ticks_active_to_start,
					  adv_iso->ull.ticks_prepare_to_start);
	} else {
		ticks_slot_overhead = 0U;
	}

	/* setup to use ISO create prepare function for first radio event */
	mfy_lll_prepare.fp = lll_adv_iso_create_prepare;

	ret_cb = TICKER_STATUS_BUSY;
	ret = ticker_start(TICKER_INSTANCE_ID_CTLR, TICKER_USER_ID_THREAD,
			   (TICKER_ID_ADV_ISO_BASE + adv_iso->lll.handle),
			   ticks_anchor, 0U,
			   HAL_TICKER_US_TO_TICKS(iso_interval_us),
			   HAL_TICKER_REMAINDER(iso_interval_us),
			   TICKER_NULL_LAZY,
			   (adv_iso->ull.ticks_slot + ticks_slot_overhead),
			   ticker_cb, adv_iso,
			   ull_ticker_status_give, (void *)&ret_cb);
	ret = ull_ticker_status_take(ret, &ret_cb);

	return ret;
}

static void mfy_iso_offset_get(void *param)
{
	struct ll_adv_sync_set *sync;
	struct lll_adv_iso *lll_iso;
	uint32_t ticks_to_expire;
	struct pdu_big_info *bi;
	uint32_t ticks_current;
	uint64_t payload_count;
	struct pdu_adv *pdu;
	uint8_t ticker_id;
	uint16_t lazy;
	uint8_t retry;
	uint8_t id;

	sync = param;
	lll_iso = sync->lll.iso;
	ticker_id = TICKER_ID_ADV_ISO_BASE + lll_iso->handle;

	id = TICKER_NULL;
	ticks_to_expire = 0U;
	ticks_current = 0U;
	retry = 4U;
	do {
		uint32_t volatile ret_cb;
		uint32_t ticks_previous;
		uint32_t ret;
		bool success;

		ticks_previous = ticks_current;

		ret_cb = TICKER_STATUS_BUSY;
		ret = ticker_next_slot_get_ext(TICKER_INSTANCE_ID_CTLR,
					       TICKER_USER_ID_ULL_LOW,
					       &id, &ticks_current,
					       &ticks_to_expire, &lazy,
					       NULL, NULL,
					       ticker_op_cb, (void *)&ret_cb);
		if (ret == TICKER_STATUS_BUSY) {
			/* Busy wait until Ticker Job is enabled after any Radio
			 * event is done using the Radio hardware. Ticker Job
			 * ISR is disabled during Radio events in LOW_LAT
			 * feature to avoid Radio ISR latencies.
			 */
			while (ret_cb == TICKER_STATUS_BUSY) {
				ticker_job_sched(TICKER_INSTANCE_ID_CTLR,
						 TICKER_USER_ID_ULL_LOW);
			}
		}

		success = (ret_cb == TICKER_STATUS_SUCCESS);
		LL_ASSERT(success);

		LL_ASSERT((ticks_current == ticks_previous) || retry--);

		LL_ASSERT(id != TICKER_NULL);
	} while (id != ticker_id);

	payload_count = lll_iso->payload_count + ((lll_iso->latency_prepare +
						   lazy) * lll_iso->bn);

	pdu = lll_adv_sync_data_latest_peek(&sync->lll);
	bi = big_info_get(pdu);
	big_info_offset_fill(bi, ticks_to_expire, 0U);
	bi->payload_count_framing[0] = payload_count;
	bi->payload_count_framing[1] = payload_count >> 8;
	bi->payload_count_framing[2] = payload_count >> 16;
	bi->payload_count_framing[3] = payload_count >> 24;
	bi->payload_count_framing[4] = payload_count >> 32;
	bi->payload_count_framing[4] &= ~0x7F;
	bi->payload_count_framing[4] |= (payload_count >> 32) & 0x7F;
}

static inline struct pdu_big_info *big_info_get(struct pdu_adv *pdu)
{
	struct pdu_adv_com_ext_adv *p;
	struct pdu_adv_ext_hdr *h;
	uint8_t *ptr;

	p = (void *)&pdu->adv_ext_ind;
	h = (void *)p->ext_hdr_adv_data;
	ptr = h->data;

	/* No AdvA and TargetA */

	/* traverse through CTE Info, if present */
	if (h->cte_info) {
		ptr += sizeof(struct pdu_cte_info);
	}

	/* traverse through ADI, if present */
	if (h->adi) {
		ptr += sizeof(struct pdu_adv_adi);
	}

	/* traverse through aux ptr, if present */
	if (h->aux_ptr) {
		ptr += sizeof(struct pdu_adv_aux_ptr);
	}

	/* No SyncInfo */

	/* traverse through Tx Power, if present */
	if (h->tx_pwr) {
		ptr++;
	}

	/* FIXME: Parse and find the Length encoded AD Format */
	ptr += 2;

	return (void *)ptr;
}

static inline void big_info_offset_fill(struct pdu_big_info *bi,
					uint32_t ticks_offset,
					uint32_t start_us)
{
	uint32_t offs;

	offs = HAL_TICKER_TICKS_TO_US(ticks_offset) - start_us;
	offs = offs / OFFS_UNIT_30_US;
	if (!!(offs >> OFFS_UNIT_BITS)) {
		bi->offs = sys_cpu_to_le16(offs / (OFFS_UNIT_300_US /
						   OFFS_UNIT_30_US));
		bi->offs_units = 1U;
	} else {
		bi->offs = sys_cpu_to_le16(offs);
		bi->offs_units = 0U;
	}
}

static void ticker_cb(uint32_t ticks_at_expire, uint32_t ticks_drift,
		      uint32_t remainder, uint16_t lazy, uint8_t force,
		      void *param)
{
	static struct lll_prepare_param p;
	struct ll_adv_iso_set *adv_iso = param;
	uint32_t ret;
	uint8_t ref;

	DEBUG_RADIO_PREPARE_A(1);

	/* Increment prepare reference count */
	ref = ull_ref_inc(&adv_iso->ull);
	LL_ASSERT(ref);

	/* Append timing parameters */
	p.ticks_at_expire = ticks_at_expire;
	p.remainder = remainder;
	p.lazy = lazy;
	p.force = force;
	p.param = &adv_iso->lll;
	mfy_lll_prepare.param = &p;

	/* Kick LLL prepare */
	ret = mayfly_enqueue(TICKER_USER_ID_ULL_HIGH, TICKER_USER_ID_LLL, 0,
			     &mfy_lll_prepare);
	LL_ASSERT(!ret);

	DEBUG_RADIO_PREPARE_A(1);
}

static void ticker_op_cb(uint32_t status, void *param)
{
	*((uint32_t volatile *)param) = status;
}

static void ticker_stop_op_cb(uint32_t status, void *param)
{
	static memq_link_t link;
	static struct mayfly mfy = {0U, 0U, &link, NULL, adv_iso_disable};
	uint32_t ret;

	LL_ASSERT(status == TICKER_STATUS_SUCCESS);

	/* Check if any pending LLL events that need to be aborted */
	mfy.param = param;
	ret = mayfly_enqueue(TICKER_USER_ID_ULL_LOW,
			     TICKER_USER_ID_ULL_HIGH, 0U, &mfy);
	LL_ASSERT(!ret);
}

static void adv_iso_disable(void *param)
{
	struct ll_adv_iso_set *adv_iso;
	struct ull_hdr *hdr;

	/* Check ref count to determine if any pending LLL events in pipeline */
	adv_iso = param;
	hdr = &adv_iso->ull;
	if (ull_ref_get(hdr)) {
		static memq_link_t link;
		static struct mayfly mfy = {0U, 0U, &link, NULL, lll_disable};
		uint32_t ret;

		mfy.param = &adv_iso->lll;

		/* Setup disabled callback to be called when ref count
		 * returns to zero.
		 */
		LL_ASSERT(!hdr->disabled_cb);
		hdr->disabled_param = mfy.param;
		hdr->disabled_cb = disabled_cb;

		/* Trigger LLL disable */
		ret = mayfly_enqueue(TICKER_USER_ID_ULL_HIGH,
				     TICKER_USER_ID_LLL, 0U, &mfy);
		LL_ASSERT(!ret);
	} else {
		/* No pending LLL events */
		disabled_cb(&adv_iso->lll);
	}
}

static void disabled_cb(void *param)
{
	static memq_link_t link;
	static struct mayfly mfy = {0U, 0U, &link, NULL, tx_lll_flush};
	uint32_t ret;

	mfy.param = param;
	ret = mayfly_enqueue(TICKER_USER_ID_ULL_HIGH,
			     TICKER_USER_ID_LLL, 0U, &mfy);
	LL_ASSERT(!ret);
}

static void tx_lll_flush(void *param)
{
	struct ll_adv_iso_set *adv_iso;
	struct lll_adv_iso *lll;
	struct node_rx_pdu *rx;
	memq_link_t *link;

	/* Get reference to ULL context */
	lll = param;
	adv_iso = HDR_LLL2ULL(lll);

	/* TODO: Flush TX */

	/* Get the terminate structure reserved in the ISO context.
	 * The terminate reason and connection handle should already be
	 * populated before this mayfly function was scheduled.
	 */
	rx = (void *)&adv_iso->node_rx_terminate;
	link = rx->hdr.link;
	LL_ASSERT(link);
	rx->hdr.link = NULL;

	/* Enqueue the terminate towards ULL context */
	ull_rx_put(link, rx);
	ull_rx_sched();
}
