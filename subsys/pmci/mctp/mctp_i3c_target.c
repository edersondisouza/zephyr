/*
 * Copyright (c) 2025 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 */

#include "zephyr/pmci/mctp/mctp_i3c_common.h"
#include <zephyr/sys/__assert.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/pmci/mctp/mctp_i3c_target.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(mctp_i3c_target, CONFIG_MCTP_LOG_LEVEL);

void mctp_i3c_target_buf_write(struct i3c_target_config *config, uint8_t *val, uint32_t len)
{
	struct mctp_binding_i3c_target *b =
		CONTAINER_OF(config, struct mctp_binding_i3c_target, i3c_target_cfg);

	b->rx_pkt = mctp_pktbuf_alloc(&b->binding, len);

	if (b->rx_pkt == NULL) {
		LOG_WRN("Could not allocate pktbuf of len %d to receive I3C message", len);
		return;
	}

	memcpy(b->rx_pkt->data, val, len);


	LOG_DBG("Buf write %d bytes", len);
	LOG_HEXDUMP_DBG(val, len, "Data");
}

int mctp_i3c_target_buf_read(struct i3c_target_config *config, uint8_t **val, uint32_t *len, uint8_t *hdr_mode)
{
	struct mctp_binding_i3c_target *b =
		CONTAINER_OF(config, struct mctp_binding_i3c_target, i3c_target_cfg);

	LOG_DBG("Buf read");

	if (b->tx_pkt == NULL || b->tx_sent) {
		return -ENODATA;
	}

	b->tx_sent = true;


	return 0;
}

int mctp_i3c_target_stop(struct i3c_target_config *config)
{
	struct mctp_binding_i3c_target *b =
		CONTAINER_OF(config, struct mctp_binding_i3c_target, i3c_target_cfg);

	LOG_DBG("Stop");
	if (b->tx_pkt != NULL && b->tx_sent) {
		LOG_DBG("msg sent");
		k_sem_give(b->tx_complete);
	}

	if (b->rx_pkt != NULL) {
		mctp_bus_rx(&b->binding, b->rx_pkt);
		b->rx_pkt = NULL;
	}

	return 0;
}

const struct i3c_target_callbacks mctp_i3c_target_callbacks = {
	.buf_write_received_cb = mctp_i3c_target_buf_write,
	.buf_read_requested_cb = mctp_i3c_target_buf_read,
	.stop_cb = mctp_i3c_target_stop,
};

/*
 * libmctp wants us to return once the packet is sent not before
 * so the entire process of flagging the tx with gpio, waiting on the read,
 * needs to complete before we can move on.
 *
 * this is called for each packet in the packet queue libmctp provides
 */
int mctp_i3c_target_tx(struct mctp_binding *binding, struct mctp_pktbuf *pkt)
{
	struct mctp_binding_i3c_target *b =
		CONTAINER_OF(binding, struct mctp_binding_i3c_target, binding);
	int r;
	LOG_DBG("TX pkt len %d", pkt->end - pkt->start);
	k_sem_take(b->tx_lock, K_FOREVER);
	LOG_DBG("TX pkt locked");

	b->tx_pkt = pkt;
	b->tx_sent = false;

	/* Need to have data at TX fifo before rising IBI */
	// TODO this may not be the case for all I3C controllers,
	// need to check
	r = i3c_target_tx_write(b->i3c, pkt->data + pkt->start,
				     pkt->end - pkt->start, 0);
	LOG_DBG("i3c_target_tx_write returned %d", r);

	uint8_t payload = MCTP_I3C_MDB_PENDING_READ;

	struct i3c_ibi ibi_req = {
		.ibi_type = I3C_IBI_TARGET_INTR,
		.payload = &payload,
		.payload_len = 1,
	};

	r = i3c_ibi_raise(b->i3c, &ibi_req);
	LOG_DBG("IBI raised %d", r);
//	k_sem_take(b->tx_complete, K_FOREVER);
	k_sem_give(b->tx_lock);
	return 0;
}

int mctp_i3c_target_start(struct mctp_binding *binding)
{
	struct mctp_binding_i3c_target *b =
		CONTAINER_OF(binding, struct mctp_binding_i3c_target, binding);
	int rc;

	/* Register i3c target */
	rc = i3c_target_register(b->i3c, &b->i3c_target_cfg);
	if (rc != 0) {
		LOG_ERR("failed to register i2c target");
		goto out;
	}
	mctp_binding_set_tx_enabled(binding, true);

out:
	return 0;
}
