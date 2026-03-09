/*
 * Copyright (c) 2016 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/sensor.h>

#include <zephyr/pmci/mctp/mctp_uart.h>

#include <libmctp.h>
#include <libpldm/entity.h>

#include <pldm.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(sensor_mctp_endpoint);

MCTP_UART_DT_DEFINE(mctp_endpoint, DEVICE_DT_GET(DT_NODELABEL(mctp_serial)));
#define LOCAL_EID 10

#if DT_NODE_HAS_STATUS(DT_ALIAS(ambient_temp0), okay)
static const struct device *const dev = DEVICE_DT_GET(DT_ALIAS(ambient_temp0));
#endif

#define REMOTE_EID 20
/* Local PLDM Terminus ID that responds to requests */
#define LOCAL_TID 2

struct message {
	uintptr_t fifo;
	size_t len;
	uint8_t src_eid;
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

#if DT_NODE_HAS_STATUS(DT_ALIAS(ambient_temp0), okay)
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
#endif

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

#if DT_NODE_HAS_STATUS(DT_ALIAS(ambient_temp0), okay)
	rc = read_temperature(&temp);
	if (rc < 0) {
		LOG_ERR("Error reading temperature sensor: %d", rc);
		*present_state = PLDM_SENSOR_UNKNOWN;
	}
#else
	(void)rc;
	/* If we don't have a real sensor, just return a dummy value */
	LOG_INF("No temperature sensor found, returning dummy value");
	temp.val1 = 8;
	temp.val2 = 500000;
#endif


	LOG_INF("Read temperature sensor, value %f", sensor_value_to_double(&temp));
	reading = sensor_value_to_deci(&temp);

	*comp_code = PLDM_SUCCESS;

	memcpy((void *)present_reading, &reading, sizeof(reading));

	return 0;
}

static void pldm_rx_work(struct k_work *item)
{
	int rc;

	while (true) {
		struct message *rx_msg = k_fifo_get(&rx_fifo, K_NO_WAIT);
		if (!rx_msg) {
			break;
		}

		LOG_INF("Processing PLDM message from mctp endpoint %d, len %zu", rx_msg->src_eid, rx_msg->len);
		LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "PLDM message");

		rc = pldm_request_handler(mctp_ctx, rx_msg->src_eid, &tid_info, all_pdrs,
					  ARRAY_SIZE(all_pdrs), &pldm_cbs,
					  (struct pldm_msg *)rx_msg->data,
					  rx_msg->len);

		LOG_DBG("PLDM request handler returned %d", rc);

		free(rx_msg);
	}
}
K_WORK_DEFINE(rx_work, pldm_rx_work);

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = msg;

	if (len < 1) {
		LOG_WRN("MCTP Message should contain a message type and integrity check byte!");
		return;
	}

	/* If the message endpoint ID matches our local endpoint ID, and its a pldm message, submit
	 * it to the work queue for processing.
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

int main(void)
{
#if DT_NODE_HAS_STATUS(DT_ALIAS(ambient_temp0), okay)
	if (!device_is_ready(dev)) {
		LOG_WRN("sensor: device not ready.\n");
		return 0;
	}
#endif

	LOG_INF("Sensor EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	LOG_INF("Supported PLDM types:");
	log_types(tid_info.types);
	log_commands(PLDM_BASE, tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_BASE)].commands);
	log_commands(PLDM_PLATFORM, tid_info.type_infos[PLDM_TYPE_INFO_IDX(PLDM_PLATFORM)].commands);

	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_register_bus(mctp_ctx, &mctp_endpoint.binding, LOCAL_EID);
	mctp_set_rx_all(mctp_ctx, rx_message, NULL);
	mctp_uart_start_rx(&mctp_endpoint);

	return 0;
}
