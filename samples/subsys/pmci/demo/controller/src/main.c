/*
 * Copyright (c) 2025 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <zephyr/types.h>
#include <zephyr/kernel.h>
#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_i2c_gpio_controller.h>
#include <zephyr/pmci/mctp/mctp_i3c_controller.h>

#include <pldm.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(controller_mctp_endpoint);

#define LOCAL_EID 20
#define SENSOR_EID DT_PROP_BY_IDX(DT_NODELABEL(mctp_i3c), endpoint_ids, 0)
#define SENSOR_ALTERNATE_EID DT_PROP_BY_IDX(DT_NODELABEL(mctp_i2c), endpoint_ids, 1)
#define DISPLAY_EID DT_PROP_BY_IDX(DT_NODELABEL(mctp_i2c), endpoint_ids, 0)

#define MCTP_MESSAGE_TYPE_MASK 0x7F
#define PLDM_MCTP_MESSAGE_TYPE 1

MCTP_I2C_GPIO_CONTROLLER_DT_DEFINE(mctp_i2c_ctrl, DT_NODELABEL(mctp_i2c));
MCTP_I3C_CONTROLLER_DT_DEFINE(mctp_i3c_ctrl, DT_NODELABEL(mctp_i3c));

struct mctp *mctp_ctx_i2c_gpio;
struct mctp *mctp_ctx_i3c;

struct temperature_data {
	double temperature;
	bool updated;
} __packed;

struct temperature_data last_temperature;

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

		LOG_DBG("Processing PLDM message from mctp endpoint %d, len %zu", rx_msg->src_eid, rx_msg->len);
		LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "PLDM message");

		pldm_response_handler((struct pldm_msg *)rx_msg->data, rx_msg->len);

		free(rx_msg);
	}
}
K_WORK_DEFINE(rx_work, pldm_rx_work);

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = (uint8_t *)msg;

	if (len < 1) {
		LOG_WRN("MCTP Message should contain a message type and integrity check byte!");
		return;
	}

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

bool find_sensor(struct mctp *mctp_ctx, uint8_t eid, struct pldm_compact_numeric_sensor_pdr *found_pdr)
{
	struct pldm_tid_info tid_info;
	int rc = pldm_discovery(mctp_ctx, eid, &tid_info);
	if (rc != 0) {
		LOG_ERR("PLDM discovery failed for EID %d, error code: %d", eid, rc);
		return false;
	}

	LOG_INF("Supported PLDM types:");
	for (int i = 0; i <= 8; i++) {
		if (is_bit_set(tid_info.types, i)) {
			LOG_INF("\tType %d", i);
			LOG_INF("\t\tVersion: %d.%d", tid_info.type_infos[i].version.major, tid_info.type_infos[i].version.minor);
			LOG_INF("\t\tSupported commands:");
			for (int cmd = 0; cmd < 256; cmd++) {
				if (is_bit_set(tid_info.type_infos[i].commands, cmd)) {
					LOG_INF("\t\t\tCommand %d", cmd);
				}
			}
		}
	}
	if (is_bit_set(tid_info.types, PLDM_OEM)) {
		LOG_INF("\tType OEM");
		LOG_INF("\t\tVersion: %d.%d", tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_OEM)].version.major, tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_OEM)].version.minor);
		LOG_INF("\t\tSupported commands:");
		for (int cmd = 0; cmd < 256; cmd++) {
			if (is_bit_set(tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_OEM)].commands, cmd)) {
				LOG_INF("\t\t\tCommand %d", cmd);
			}
		}
	}

	if (!is_bit_set(tid_info.types, PLDM_PLATFORM) ||
	    !is_bit_set(tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_PLATFORM)].commands, PLDM_GET_PDR)) {
		LOG_INF("Endpoint %d does not support PLDM platform type or Get PDR command", eid);
		return false;
	}

	uint8_t pdr_buf[128];
	size_t pdr_len = sizeof(pdr_buf);
	struct pldm_pdr_hdr *pdr_hdr = (struct pldm_pdr_hdr *)pdr_buf;
	rc = pldm_get_pdr(mctp_ctx, eid, 0, pdr_buf, &pdr_len);
	if (rc != 0) {
		LOG_ERR("Failed to retrieve PDR from EID %d, error code: %d", eid, rc);
		return false;
	}

	/* Ensure it's a compact numeric sensor and that it is a temperature one */
	if (pdr_hdr->type == PLDM_COMPACT_NUMERIC_SENSOR_PDR) {
		struct pldm_compact_numeric_sensor_pdr *sensor_pdr = (struct pldm_compact_numeric_sensor_pdr *)pdr_buf;
		if (sensor_pdr->base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ||
		    sensor_pdr->base_unit == PLDM_SENSOR_UNIT_DEGRESS_F) {
			LOG_INF("PDR is a Compact Numeric Sensor:");
			LOG_INF("\tSensor ID: %d", sensor_pdr->sensor_id);

			*found_pdr = *sensor_pdr;
			return true;
		}
	}

	LOG_INF("No suitable temperature sensor PDR found for EID %d", eid);
	return false;
}

int main(void)
{
	LOG_INF("Controller EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	struct pldm_compact_numeric_sensor_pdr sensor_pdr = { };
	struct mctp *sensor_ctx = NULL;
	uint8_t sensor_eid = 0;
	int rc;

	mctp_set_alloc_ops(malloc, free, realloc);
	mctp_ctx_i3c = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx_i3c != NULL);
	mctp_ctx_i2c_gpio = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx_i2c_gpio != NULL);
	mctp_register_bus(mctp_ctx_i3c, &mctp_i3c_ctrl.binding, LOCAL_EID);
	mctp_register_bus(mctp_ctx_i2c_gpio, &mctp_i2c_ctrl.binding, LOCAL_EID);
	mctp_set_rx_all(mctp_ctx_i3c, rx_message, NULL);
	mctp_set_rx_all(mctp_ctx_i2c_gpio, rx_message, NULL);

	if (!find_sensor(mctp_ctx_i3c, SENSOR_EID, &sensor_pdr)) {
		if (!find_sensor(mctp_ctx_i2c_gpio, SENSOR_ALTERNATE_EID, &sensor_pdr)) {
			LOG_WRN("No valid temperature sensor PDR found on either bus, cannot send data to display");
			return 0;
		} else {
			LOG_INF("Found valid temperature sensor PDR on I2C GPIO bus, using that one");
			sensor_ctx = mctp_ctx_i2c_gpio;
			sensor_eid = SENSOR_ALTERNATE_EID;
		}
	} else {
		LOG_INF("Found valid temperature sensor PDR on I3C bus, using that one");
		sensor_ctx = mctp_ctx_i3c;
		sensor_eid = SENSOR_EID;
	}

	while (true) {
		uint8_t present_state;
		int32_t reading; /* Assume sensor returns signed 32 */
		size_t reading_len = sizeof(reading);

		LOG_INF("Reading temperature from sensor %d", sensor_pdr.sensor_id);
		rc = pldm_get_sensor_reading(sensor_ctx, sensor_eid, sensor_pdr.sensor_id, &reading,
					     &reading_len, &present_state);

		if (rc == 0) {
			LOG_INF("Current temperature: %.2f%c, present state: %d",
				last_temperature.temperature,
				sensor_pdr.base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ? 'C' : 'F',
				present_state);

			if (present_state == PLDM_SENSOR_NORMAL) {
				last_temperature.updated = true;
				last_temperature.temperature = reading *
					pow(10, sensor_pdr.unit_modifier);

				if (sensor_pdr.base_unit == PLDM_SENSOR_UNIT_DEGRESS_F) {
					last_temperature.temperature =
						(last_temperature.temperature - 32) * 5 / 9;
				}
			} else {
				LOG_WRN("Sensor reading is unavailable");
			}
		} else {
			LOG_WRN("Failed to get sensor reading, error code: %d", rc);
		}

		LOG_INF("Sending message to Display EID:");
		LOG_INF("\tTemperature: %.2f°C - Up-to-date: %d",
			last_temperature.temperature, last_temperature.updated);
		mctp_message_tx(mctp_ctx_i2c_gpio, DISPLAY_EID, false, 0, &last_temperature,
				sizeof(last_temperature));
		last_temperature.updated = false;

		k_sleep(K_SECONDS(2));
	}

	return 0;
}
