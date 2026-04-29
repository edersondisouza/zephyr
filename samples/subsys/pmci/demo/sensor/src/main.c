/*
 * Copyright (c) 2016 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <stdio.h>
#include <zephyr/drivers/sensor.h>

#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_i3c_target.h>

#include <libpldm/entity.h>
#include <libmctp-cmds.h>
#include <control.h>

#include <pldm.h>
#include <mctp.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(sensor_mctp_endpoint);

MCTP_I3C_TARGET_DT_DEFINE(mctp_endpoint, DT_NODELABEL(mctp_i3c));
#define LOCAL_EID DT_PROP(DT_NODELABEL(mctp_i3c), endpoint_id)

static const struct device *const dev = DEVICE_DT_GET_ONE(seeed_grove_temperature);

#define REMOTE_EID 20
/* Local PLDM Terminus ID that responds to requests */
#define LOCAL_TID 2

struct message {
	uintptr_t fifo;
	size_t len;
	uint8_t src_eid;
	bool tag_owner;
	uint8_t msg_tag;
	struct mctp_binding *binding;
	uint8_t data[];
};

K_FIFO_DEFINE(rx_fifo);

static struct mctp *mctp_ctx;

static struct pldm_tid_info tid_info = {
	.tid = LOCAL_EID,
	.types = {
		{ .byte = BIT(PLDM_BASE) | BIT(PLDM_PLATFORM)},
		{ 0 },
	},
	.type_infos = {
		[PLDM_BASE] = {
			.version = {
				.major = 1,
			},
			.commands = {
				{ .byte = BIT(PLDM_GET_TID)  | BIT(PLDM_GET_PLDM_VERSION) |
					  BIT(PLDM_GET_PLDM_TYPES) | BIT(PLDM_GET_PLDM_COMMANDS)
				},
				{ 0 },
			},
		},
		[PLDM_PLATFORM] = {
			.version = {
				.major = 1,
			},
			.commands = {
				[PLDM_GET_SENSOR_READING / 8] = {
					.byte = BIT(PLDM_GET_SENSOR_READING % 8)
				},
				[PLDM_GET_PDR_REPOSITORY_INFO / 8] = {
					.byte = BIT(PLDM_GET_PDR % 8)
				},
				{ 0 },
			},
		}
	},
};

static struct pldm_compact_numeric_sensor_pdr sensor_pdr = {
	.hdr = {
		.record_handle = 0,
		.version = 1,
		.type = PLDM_COMPACT_NUMERIC_SENSOR_PDR,
		.record_change_num = 0,
		.length = sys_cpu_to_le16(sizeof(struct pldm_compact_numeric_sensor_pdr) -
					  sizeof(struct pldm_pdr_hdr)),
	},
	.terminus_handle = sys_cpu_to_le16(LOCAL_TID),
	.sensor_id = sys_cpu_to_le16(1),
	.entity_type = sys_cpu_to_le16(PLDM_ENTITY_TERMINUS | (1 << 15)),
	.entity_instance = sys_cpu_to_le16(1),
	.container_id = 0,
	.sensor_name_length = 0,
	.base_unit = PLDM_SENSOR_UNIT_DEGRESS_C,
	.unit_modifier = -1,
	.occurrence_rate = PLDM_RATE_UNIT_NONE,
	.range_field_support.byte = 0,
	.warning_high = sys_cpu_to_le32(100),
	.warning_low = sys_cpu_to_le32(-100),
	.critical_high = sys_cpu_to_le32(150),
	.critical_low = sys_cpu_to_le32(-150),
	.fatal_high = sys_cpu_to_le32(200),
	.fatal_low = sys_cpu_to_le32(-200),
};

static struct pldm_pdr_hdr *all_pdrs[] = {
	(struct pldm_pdr_hdr *)&sensor_pdr,
};

static int sensor_reading_cb(uint16_t sensor_id, bool8_t rearm, uint8_t *comp_code, uint8_t *sensor_data_size,
		      uint8_t *sensor_operational_state, uint8_t *sensor_event_message_enable,
		      uint8_t *present_state, uint8_t *previous_state, uint8_t *event_state,
		      const uint8_t *present_reading);

static struct pldm_commands_cb pldm_cbs = {
	.numeric_sensor_reading = sensor_reading_cb,
};

int read_temperature(struct sensor_value *val)
{
	int ret;

	ret = sensor_sample_fetch_chan(dev, SENSOR_CHAN_AMBIENT_TEMP);
	if (ret < 0) {
		LOG_ERR("Could not fetch temperature: %d", ret);
		return ret;
	}

	ret = sensor_channel_get(dev, SENSOR_CHAN_AMBIENT_TEMP, val);
	if (ret < 0) {
		LOG_ERR("Could not get temperature: %d", ret);
	}
	return ret;
}

static int sensor_reading_cb(uint16_t sensor_id, bool8_t rearm, uint8_t *comp_code, uint8_t *sensor_data_size,
			      uint8_t *sensor_operational_state, uint8_t *sensor_event_message_enable,
			      uint8_t *present_state, uint8_t *previous_state, uint8_t *event_state,
			      const uint8_t *present_reading)
{

	struct sensor_value temp;
	int32_t reading;
	int rc;

	*sensor_data_size = PLDM_SENSOR_DATA_SIZE_SINT32;
	*sensor_operational_state = PLDM_SENSOR_ENABLED;
	*sensor_event_message_enable = PLDM_NO_EVENT_GENERATION;
	*present_state = PLDM_SENSOR_NORMAL;
	*previous_state = PLDM_SENSOR_UNKNOWN;
	*event_state = PLDM_SENSOR_NORMAL;

	rc = read_temperature(&temp);
	if (rc < 0) {
		LOG_ERR("Error reading temperature sensor: %d", rc);
		*present_state = PLDM_SENSOR_UNKNOWN;
	}

	LOG_INF("Read temperature sensor, value %f", sensor_value_to_double(&temp));
	reading = sensor_value_to_deci(&temp);

	*comp_code = PLDM_SUCCESS;

	memcpy((void *)present_reading, &reading, sizeof(reading));

	return 0;
}

static bool  msg_type_versions(uint8_t msg_type, uint32_t **versions, size_t *num_versions)
{
	/* 1.2 On MCTP BCD Version encoding */
	static const uint8_t version[] = { 0xf1, 0xf2, 0xff, 0x00 };

	if (msg_type == PLDM_MCTP_MESSAGE_TYPE) {
		*versions = (uint32_t *)&version;
		*num_versions = 1;
		return true;
	}

	return false;
}

static void mctp_rx_work(struct k_work *item)
{
	int rc;

	while (true) {
		struct message *rx_msg = k_fifo_get(&rx_fifo, K_NO_WAIT);
		if (!rx_msg) {
			break;
		}

		switch (rx_msg->data[0] & MCTP_MESSAGE_TYPE_MASK) {
		case PLDM_MCTP_MESSAGE_TYPE: {

				LOG_INF("Processing PLDM message from mctp endpoint %d, len %zu", rx_msg->src_eid, rx_msg->len);
				LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "PLDM message");

				rc = pldm_request_handler(mctp_ctx, rx_msg->src_eid, &tid_info, all_pdrs,
							  ARRAY_SIZE(all_pdrs), &pldm_cbs,
							  (struct pldm_msg *)&rx_msg->data[1],
							  rx_msg->len - 1);

				LOG_DBG("PLDM request handler returned %d", rc);
			}
			break;
		case MCTP_CTRL_HDR_MSG_TYPE: {
				LOG_INF("Processing MCTP control message from mctp endpoint %d, len %zu", rx_msg->src_eid, rx_msg->len);
				LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "MCTP control message");


				mctp_control_request_handler(rx_msg->binding, rx_msg->src_eid, rx_msg->tag_owner,
							     rx_msg->msg_tag, rx_msg->data, rx_msg->len,
							     msg_type_versions);
			}
			break;
		}

		free(rx_msg);
	}
}
K_WORK_DEFINE(rx_work, mctp_rx_work);

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = msg;
	struct message *rx_msg;

	if (len < 1) {
		LOG_WRN("MCTP Message should contain a message type and integrity check byte!");
		return;
	}

	/* If the message endpoint ID matches our local endpoint ID, submit
	 * it to the work queue for processing.
	 */
	rx_msg = malloc(sizeof(struct message) + len);

	if (!rx_msg) {
		LOG_ERR("Failed to allocate memory for incoming message");
		return;
	}
	rx_msg->len = len;
	rx_msg->src_eid = src_eid;
	rx_msg->tag_owner = tag_owner;
	rx_msg->msg_tag = msg_tag;
	rx_msg->binding = data;
	memcpy(rx_msg->data, msg_buf, len);
	k_fifo_put(&rx_fifo, rx_msg);
	k_work_submit(&rx_work);
}

int main(void)
{
	if (!device_is_ready(dev)) {
		LOG_WRN("sensor: device not ready.\n");
		return 0;
	}

	LOG_INF("Sensor EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

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
	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_register_bus(mctp_ctx, &mctp_endpoint.binding, LOCAL_EID);
	mctp_set_rx_all(mctp_ctx, rx_message, &mctp_endpoint.binding);
	mctp_control_add_type(mctp_ctx, PLDM_MCTP_MESSAGE_TYPE);
	/* For some reason, libmctp doesn't add the base type by default */
	mctp_control_add_type(mctp_ctx, MCTP_MSG_TYPE_NUMBER_MCTP_BASE);
#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
	mctp_uart_start_rx(&mctp_endpoint);
#endif

	return 0;
}
