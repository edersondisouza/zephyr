/*
 * Copyright (c) 2025 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <zephyr/types.h>
#include <zephyr/kernel.h>
#include <libpldm/base.h>
#include <libpldm/platform.h>
#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_uart.h>

#include <pldm.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(pldm_host);

/* PLDM MCTP Message Type */
#define PLDM_MCTP_MESSAGE_TYPE 1

/* Local MCTP Endpoint ID that responds to requests */
#define LOCAL_EID 20
/* Local PLDM Terminus ID that responds to requests */
#define LOCAL_TID 1

/* Remote serial MCTP Endpoint ID that we respond to */
#define SERIAL_REMOTE_EID 10

struct mctp_endpoint {
	uint8_t eid;
	struct mctp *mctp_ctx;
};

struct message {
	uintptr_t fifo;
	size_t len;
	uint8_t src_eid;
	uint8_t data[];
};
K_FIFO_DEFINE(rx_fifo);

static void pldm_rx_work(struct k_work *item)
{
	while (true) {
		struct message *rx_msg = k_fifo_get(&rx_fifo, K_NO_WAIT);
		if (!rx_msg) {
			break;
		}

		LOG_DBG("Processing PLDM message from mctp endpoint %d, len %zu", rx_msg->src_eid,
			rx_msg->len);
		LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "PLDM message");

		pldm_response_handler((struct pldm_msg *)rx_msg->data, rx_msg->len);

		free(rx_msg);
	}
}
K_WORK_DEFINE(rx_work, pldm_rx_work);

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	LOG_DBG("Received message from mctp endpoint %d, msg_tag %d, len %zu", src_eid, msg_tag,
		len);
	LOG_HEXDUMP_DBG(msg, len, "mctp rx message");

	if (len < 1) {
		LOG_ERR("MCTP Message should contain a message type and integrity check byte!");
		return;
	}

	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = msg;

	/* if the message endpoint id matches our local endpoint id, and its a pldm message, call
	 * the pldm_rx_message call
	 */
	if ((msg_buf[0] & MCTP_MESSAGE_TYPE_MASK) == PLDM_MCTP_MESSAGE_TYPE) {
		size_t pldm_msg_len = len - 1;
		struct message *rx_msg = malloc(sizeof(struct message) + pldm_msg_len);

		if (!rx_msg) {
			LOG_ERR("Failed to allocate memory for incoming PLDM message");
			return;
		}

		rx_msg->len = pldm_msg_len;
		rx_msg->src_eid = src_eid;
		memcpy(rx_msg->data, &msg_buf[1], pldm_msg_len);
		k_fifo_put(&rx_fifo, rx_msg);
		k_work_submit(&rx_work);
	}
}

MCTP_UART_DT_DEFINE(mctp_host_serial, DEVICE_DT_GET(DT_NODELABEL(mctp_serial)));

struct mctp_endpoint init_mctp_uart(struct mctp_binding_uart *uart)
{
	struct mctp_endpoint endpoint;

	endpoint.mctp_ctx = mctp_init();
	if (endpoint.mctp_ctx == NULL) {
		LOG_ERR("Failed to initialize MCTP context on serial");
		return endpoint;
	}

	mctp_register_bus(endpoint.mctp_ctx, &uart->binding, LOCAL_EID);
	mctp_set_rx_all(endpoint.mctp_ctx, rx_message, NULL);
	mctp_uart_start_rx(uart);

	endpoint.eid = SERIAL_REMOTE_EID;

	return endpoint;
}

void probe(struct mctp *mctp_ctx, uint8_t eid)
{
	struct pldm_compact_numeric_sensor_pdr *sensor_pdr;
	uint8_t pdr_buf[128];
	size_t pdr_len = sizeof(pdr_buf);
	struct pldm_pdr_hdr *pdr_hdr = (struct pldm_pdr_hdr *)pdr_buf;
	struct pldm_tid_info tid_info;
	uint8_t present_state;
	int32_t reading; /* Assume sensor returns signed 32 */
	size_t reading_len = sizeof(reading);
	int rc;

	rc = pldm_discovery(mctp_ctx, eid, &tid_info);

	if (rc != 0) {
		LOG_ERR("PLDM discovery failed for EID %d, error code: %d", eid, rc);
		return;
	}

	LOG_INF("Supported PLDM types:");
	log_types(tid_info.types);

	if (!is_bit_set(tid_info.types, PLDM_PLATFORM) ||
	    !is_bit_set(tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_PLATFORM)].commands,
		        PLDM_GET_PDR)) {
		LOG_INF("Endpoint %d does not support PLDM platform type or Get PDR command", eid);
		return;
	}

	rc = pldm_get_pdr(mctp_ctx, eid, 0, pdr_buf, &pdr_len);
	if (rc != 0) {
		LOG_ERR("Failed to retrieve PDR from EID %d, error code: %d", eid, rc);
		return;
	}

	log_commands(PLDM_BASE, tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_BASE)].commands);
	log_commands(PLDM_PLATFORM,
		     tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_PLATFORM)].commands);

	/* Ensure it's a compact numeric sensor and that it is a temperature one */
	if (pdr_hdr->type == PLDM_COMPACT_NUMERIC_SENSOR_PDR) {
		sensor_pdr = (struct pldm_compact_numeric_sensor_pdr *)pdr_buf;
		if (sensor_pdr->base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ||
		    sensor_pdr->base_unit == PLDM_SENSOR_UNIT_DEGRESS_F) {
			LOG_INF("PDR is a Compact Numeric Sensor:");
			LOG_INF("\tSensor ID: %d", sensor_pdr->sensor_id);
		} else {
			LOG_INF("PDR record is a compact numeric sensor but not a temperature "
				"sensor, base unit %d", sensor_pdr->base_unit);
			return;
		}
	} else {
		LOG_INF("PDR record is not a compact numeric sensor, type %d", pdr_hdr->type);
		return;
	}

	/* Get sensor reading */
	rc = pldm_get_sensor_reading(mctp_ctx, eid, sensor_pdr->sensor_id, &reading, &reading_len,
				     &present_state);

	if (rc != 0) {
		LOG_ERR("Failed to get sensor reading from EID %d, error code: %d", eid, rc);
		return;
	}

	if (present_state != PLDM_SENSOR_NORMAL) {
		LOG_WRN("Sensor is in non-normal present state %d", present_state);
		return;
	}

	LOG_INF("Sensor reading is %.1f degrees %s",
		reading * pow(10, sensor_pdr->unit_modifier),
		sensor_pdr->base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ? "C" : "F");
}

int main(void)
{
	struct mctp_endpoint endpoint;

	LOG_INF("PLDM Host EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	endpoint = init_mctp_uart(&mctp_host_serial);
	if (endpoint.mctp_ctx == NULL) {
		return 0;
	}

	/* Do the PLDM discovery and get sensor reading */
	probe(endpoint.mctp_ctx, endpoint.eid);

	return 0;
}
