/*
 * Copyright (c) 2020 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#define LL_SYNC_STATE_IDLE       0x00
#define LL_SYNC_STATE_ADDR_MATCH 0x01
#define LL_SYNC_STATE_CREATED    0x02

#if defined(CONFIG_BT_CTLR_SYNC_ISO)
struct ll_sync_iso_set;
#endif /* CONFIG_BT_CTLR_SYNC_ISO */

struct ll_sync_set {
	struct ull_hdr ull;
	struct lll_sync lll;

	uint16_t skip;
	uint16_t timeout;
	uint16_t volatile timeout_reload; /* Non-zero when sync established */
	uint16_t timeout_expire;

#if defined(CONFIG_BT_CTLR_CHECK_SAME_PEER_SYNC) || \
	defined(CONFIG_BT_CTLR_SYNC_PERIODIC_ADI_SUPPORT)
	uint8_t peer_id_addr[BDADDR_SIZE];
	uint8_t peer_id_addr_type:1;
#endif /* CONFIG_BT_CTLR_CHECK_SAME_PEER_SYNC ||
	* CONFIG_BT_CTLR_SYNC_PERIODIC_ADI_SUPPORT
	*/

#if defined(CONFIG_BT_CTLR_SYNC_PERIODIC_ADI_SUPPORT)
	uint8_t nodups:1;
#endif

#if defined(CONFIG_BT_CTLR_SYNC_PERIODIC_CTE_TYPE_FILTERING) && \
	!defined(CONFIG_BT_CTLR_CTEINLINE_SUPPORT)
	/* Member used to notify event done handler to terminate sync scanning.
	 * Used only when no HW support for parsing PDU for CTEInfo.
	 */
	uint8_t sync_term:1;
#endif /* CONFIG_BT_CTLR_SYNC_PERIODIC_CTE_TYPE_FILTERING && !CONFIG_BT_CTLR_CTEINLINE_SUPPORT */

	uint8_t sync_expire:3; /* countdown of 6 before fail to establish */

#if defined(CONFIG_BT_CTLR_CHECK_SAME_PEER_SYNC)
	uint8_t sid;
#endif /* CONFIG_BT_CTLR_CHECK_SAME_PEER_SYNC */

	/* node rx type with memory aligned storage for sync lost reason.
	 * HCI will reference the value using the pdu member of
	 * struct node_rx_pdu.
	 */
	struct {
		struct node_rx_hdr hdr;
		union {
			uint8_t    pdu[0] __aligned(4);
			uint8_t    reason;
		};
	} node_rx_lost;

	struct node_rx_hdr *node_rx_sync_estab;

#if defined(CONFIG_BT_CTLR_SYNC_ISO)
	struct {
		struct node_rx_hdr *node_rx_estab;

		/* Non-Null when creating sync, reset in ISR context on
		 * synchronisation state and checked in Thread context when
		 * cancelling sync create, hence the volatile keyword.
		 */
		struct ll_sync_iso_set *volatile sync_iso;
	} iso;
#endif /* CONFIG_BT_CTLR_SYNC_ISO */
};

struct node_rx_sync {
	uint8_t status;
	uint8_t  phy;
	uint16_t interval;
	uint8_t  sca;
};

#if defined(CONFIG_BT_CTLR_SYNC_ISO)
struct ll_sync_iso_set {
	struct ull_hdr ull;
	struct lll_sync_iso lll;

	/* Periodic Advertising Sync that contained the BIGInfo */
	struct ll_sync_set *sync;

	uint16_t iso_interval;
	uint16_t timeout;

	uint16_t volatile timeout_reload; /* Non-zero when sync established */
	uint16_t timeout_expire;

	/* node rx type with memory aligned storage for sync lost reason.
	 * HCI will reference the value using the pdu member of
	 * struct node_rx_pdu.
	 */
	struct {
		struct node_rx_hdr hdr;
		union {
			uint8_t pdu[0] __aligned(4);
			struct {
				uint8_t handle;
				uint8_t reason;
			};
		};
	} node_rx_lost;
};

struct node_rx_sync_iso {
	uint8_t status;
	uint16_t interval;
};
#endif /* CONFIG_BT_CTLR_SYNC_ISO */
