/*
 * Copyright (c) 2025 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <unistd.h>
#include <zephyr/types.h>
#include <zephyr/kernel.h>
#include <libpldm/base.h>
#include <libpldm/edac.h>
#include <libpldm/entity.h>
#include <libpldm/platform.h>
#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_uart.h>
#include <zephyr/pmci/mctp/mctp_i2c_gpio_target.h>
#include <zephyr/drivers/sensor.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(pldm_endpoint);

/* PLDM MCTP Message Type */
#define PLDM_MCTP_MESSAGE_TYPE 1

/* Local MCTP Endpoint ID that responds to requests */
#define SERIAL_LOCAL_EID 10
/* Local PLDM Terminus ID that responds to requests */
#define LOCAL_TID 2

/* Remote MCTP Endpoint ID that we request from to */
#define REMOTE_EID 20

#define MCTP_INTEGRITY_CHECK   0x80
#define MCTP_MESSAGE_TYPE_MASK 0x7F

const char *MESSAGE_TYPE_TO_STRING[] = {"Response", "Request", "Reserved", "Async Request Notify"};

const char *COMMAND_TO_STRING[] = {"UNDEFINED",      "SetTID",          "GetTID",
				   "GetPLDMVersion", "GetPLDMTypes", "GetPLDMCommands",
				   "SelectPLDMVersion"};

struct message {
	struct k_work work;
	uint8_t *data;
	size_t len;
	uint8_t src_eid;
};

static struct message rx_msg_work;

static struct mctp *mctp_ctx;

int read_temperature(const struct device *dev, struct sensor_value *val)
{
	int ret;

	ret = sensor_sample_fetch_chan(dev, SENSOR_CHAN_AMBIENT_TEMP);
	if (ret < 0) {
		printf("Could not fetch temperature: %d\n", ret);
		return ret;
	}

	ret = sensor_channel_get(dev, SENSOR_CHAN_AMBIENT_TEMP, val);
	if (ret < 0) {
		printf("Could not get temperature: %d\n", ret);
	}
	return ret;
}

//static void pldm_rx_handler(uint8_t src_eid, void *data, struct pldm_msg_hdr *msg_hdr, void *msg,
//			    size_t msg_len)
static void pldm_rx_handler(struct k_work *item)
{
	struct pldm_header_info hdr_info;
	const char *message_type_str = "";
	const char *command_str = "";
	int rc;

	struct message *rx_msg = CONTAINER_OF(item, struct message, work);
	uint8_t src_eid = rx_msg->src_eid;

	LOG_INF("PLDM RX Handler called");

	struct pldm_msg *msg = (struct pldm_msg *)rx_msg->data;
	size_t msg_len = rx_msg->len - sizeof(struct pldm_msg_hdr);

	rc = unpack_pldm_header(&msg->hdr, &hdr_info);
	if (rc != 0) {
		LOG_ERR("Failed unpacking pldm header");
	}

	if (hdr_info.msg_type < ARRAY_SIZE(MESSAGE_TYPE_TO_STRING)) {
		message_type_str = MESSAGE_TYPE_TO_STRING[hdr_info.msg_type];
	}

	if (hdr_info.command < ARRAY_SIZE(COMMAND_TO_STRING)) {
		command_str = COMMAND_TO_STRING[hdr_info.command];
	}

	LOG_INF("received pldm message from mctp endpoint %d len %zu message type %d (%s) command "
		"%d (%s)",
		src_eid, msg_len, hdr_info.msg_type, message_type_str, hdr_info.command,
		command_str);

	/* Handle the GetTID command */
	if (hdr_info.command == PLDM_GET_TID && hdr_info.msg_type == PLDM_REQUEST) {
		/* Response buffer for the GetTID command needs
		 * pldm response header (4 bytes) + 1 bytes (the tid is 1 byte) + 1 byte (mctp
		 * message type byte)
		 */
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(sizeof(struct pldm_get_tid_resp)) + 1];

		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		rc = encode_get_tid_resp(hdr_info.instance, PLDM_SUCCESS, LOCAL_TID,
				    (struct pldm_msg *)&resp_msg_buf[1]);
		LOG_INF("Encoding GetTID response rc %d", rc);
		LOG_WRN("!Are we in ISR? %d", k_is_in_isr());
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		LOG_INF("Sent GetTID response to endpoint %d", src_eid);
		__ASSERT(rc == 0, "Sending response to GetTID should succeed");
	} else if (hdr_info.command == PLDM_GET_PLDM_TYPES && hdr_info.msg_type == PLDM_REQUEST) {
		/* Response buffer for the GetTID command needs
		 * pldm response header (4 bytes) + 1 bytes (the tid is 1 byte) + 1 byte (mctp
		 * message type byte)
		 */
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(PLDM_GET_TYPES_RESP_BYTES) + 1];
		const bitfield8_t types[8] = {
			{ .byte = BIT(PLDM_BASE) | BIT(PLDM_PLATFORM)},
			{ 0 },
		};
		
		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		rc = encode_get_types_resp(hdr_info.instance, PLDM_SUCCESS, types,
				    (struct pldm_msg *)&resp_msg_buf[1]);
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		__ASSERT(rc == 0, "Sending response to GetTypes should succeed");
	} else if (hdr_info.command == PLDM_GET_PLDM_VERSION && hdr_info.msg_type == PLDM_REQUEST) {
		uint32_t transfer_handle;
		uint8_t transfer_opflag;
		uint8_t type;

		rc = decode_get_version_req(msg, msg_len, &transfer_handle, &transfer_opflag, &type);
		__ASSERT(rc == PLDM_SUCCESS, "Decoding GetVersion request should succeed");
		printk("Decoded GetVersion request, transfer handle %u, transfer opflag %u, type %u\n",
		       transfer_handle, transfer_opflag, type);

		if ((type != PLDM_BASE && type != PLDM_PLATFORM)) {
			LOG_WRN("Unsupported type requested in GetPLDMVersion: %d", type);
			return;
		}

		
		/* Response buffer for the GetTID command needs
		 * pldm response header (4 bytes) + 1 bytes (the tid is 1 byte) + 1 byte (mctp
		 * message type byte)
		 */
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(PLDM_GET_VERSION_RESP_BYTES) + 1];
		ver32_t version = { .major = 1 };
		
		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		rc = encode_get_version_resp(hdr_info.instance, PLDM_SUCCESS, 0, 0, &version, sizeof(ver32_t),
				    (struct pldm_msg *)&resp_msg_buf[1]);
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		__ASSERT(rc == 0, "Sending response to GetVersion should succeed");
	} else if (hdr_info.command == PLDM_GET_PLDM_COMMANDS && hdr_info.msg_type == PLDM_REQUEST) {
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(PLDM_GET_COMMANDS_RESP_BYTES) + 1];
		bitfield8_t commands[32] = { 0 };
		uint8_t type;
		ver32_t vers;

		rc = decode_get_commands_req(msg, PLDM_GET_COMMANDS_REQ_BYTES, &type, &vers);
		__ASSERT(rc == PLDM_SUCCESS, "Decoding GetCommands request should succeed");
		printk("Decoded GetCommands request, type %u, version %u.%u\n", type, vers.major, vers.minor);

		if ((type != PLDM_BASE && type != PLDM_PLATFORM)) {
			LOG_WRN("Unsupported type requested in GetPLDMCommands: %d", type);
			return;
		}

		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		if (type == PLDM_BASE) {
			commands[0].byte = BIT(PLDM_GET_TID) | BIT(PLDM_GET_PLDM_VERSION) |
					  BIT(PLDM_GET_PLDM_TYPES) | BIT(PLDM_GET_PLDM_COMMANDS);
		} else if (type == PLDM_PLATFORM) {
			commands[PLDM_GET_SENSOR_READING / 8].byte = BIT(PLDM_GET_SENSOR_READING % 8);
			commands[PLDM_GET_PDR_REPOSITORY_INFO / 8].byte = BIT(PLDM_GET_PDR_REPOSITORY_INFO % 8) |
									 BIT(PLDM_GET_PDR % 8);
		}

		rc = encode_get_commands_resp(hdr_info.instance, PLDM_SUCCESS, commands,
				    (struct pldm_msg *)&resp_msg_buf[1]);
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		__ASSERT(rc == 0, "Sending response to GetCommands should succeed");
	} else if (hdr_info.command == PLDM_GET_PDR && hdr_info.msg_type == PLDM_REQUEST) {
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(PLDM_GET_PDR_MIN_RESP_BYTES + PLDM_PDR_NUMERIC_SENSOR_PDR_MIN_LENGTH) + 1];

		// TODO decode request and only reply if asking for the first

		/* No encode on libpldm for the PDR itself, only the common part, so do it manually =/ */
		struct pldm_compact_numeric_sensor_pdr sensor_pdr = {
			.hdr = {
				.record_handle = 0,
				.version = 1,
				.type = PLDM_COMPACT_NUMERIC_SENSOR_PDR,
				.record_change_num = 0,
				.length = sys_cpu_to_le16(sizeof(struct pldm_compact_numeric_sensor_pdr)),
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

		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		rc = encode_get_pdr_resp(hdr_info.instance, PLDM_SUCCESS, 0, 0,
					 PLDM_PLATFORM_TRANSFER_START_AND_END, sizeof(sensor_pdr),
					 (uint8_t *)&sensor_pdr,
					 pldm_edac_crc8((uint8_t *)&sensor_pdr, sizeof(sensor_pdr)),
					 (struct pldm_msg *)&resp_msg_buf[1]);
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		__ASSERT(rc == 0, "Sending response to GetPDR should succeed");
	} else if (hdr_info.command == PLDM_GET_SENSOR_READING && hdr_info.msg_type == PLDM_REQUEST) {
		const struct device *const dev = DEVICE_DT_GET(DT_ALIAS(ambient_temp0));
		struct sensor_value value;
		/* There's already one byte for the reading, so only need to add sizeof(int32_t) - 1 */
		uint8_t resp_msg_buf[PLDM_MSG_SIZE(PLDM_GET_SENSOR_READING_MIN_RESP_BYTES) + (sizeof(int32_t) - 1) + 1];
		uint16_t sensor_id;
		bool8_t rearm;
		uint8_t sensor_data_size = PLDM_SENSOR_DATA_SIZE_SINT32;
		uint8_t sensor_operation_state = PLDM_SENSOR_ENABLED;
		uint8_t sensor_event_message_enable = PLDM_NO_EVENT_GENERATION;
		uint8_t present_state = PLDM_SENSOR_NORMAL;
		uint8_t previous_state = PLDM_SENSOR_UNKNOWN;
		uint8_t event_state = PLDM_SENSOR_NORMAL;
		int32_t reading;

		rc = decode_get_sensor_reading_req(msg, msg_len, &sensor_id, &rearm);
		__ASSERT(rc == PLDM_SUCCESS, "Decoding GetSensorReading request should succeed");

		if (sensor_id != 1) {
			LOG_WRN("Unsupported sensor ID requested in GetSensorReading: %d", sensor_id);
			return;
		}

		rc = read_temperature(dev, &value);
		if (rc < 0) {
			LOG_ERR("Error reading temperature sensor: %d", rc);
			present_state = PLDM_SENSOR_UNKNOWN;
		}

		LOG_INF("Read temperature sensor, value %f", sensor_value_to_double(&value));
		reading = sensor_value_to_deci(&value);
		LOG_INF("Converted temperature reading to deci-degrees: %d", reading);

		rc = encode_get_sensor_reading_resp(hdr_info.instance, PLDM_SUCCESS, sensor_data_size, sensor_operation_state,
						 sensor_event_message_enable, present_state,
						 previous_state, event_state, (const uint8_t *) &reading,
						 (struct pldm_msg *)&resp_msg_buf[1],
						 PLDM_GET_SENSOR_READING_MIN_RESP_BYTES + (sizeof(int32_t) - 1));
		__ASSERT(rc == PLDM_SUCCESS, "Encoding pldm response should succeed");

		resp_msg_buf[0] = PLDM_MCTP_MESSAGE_TYPE;

		rc = mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf,
				     sizeof(resp_msg_buf));
		__ASSERT(rc == 0, "Sending response to GetSensorReading should succeed");

		LOG_HEXDUMP_INF(resp_msg_buf, sizeof(resp_msg_buf), "GetSensorReading response");
	} else {
		LOG_WRN("Unhandled pldm message, command %d, type %d", hdr_info.command, hdr_info.msg_type);
	}
}

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	LOG_INF("received message from mctp endpoint %d, msg_tag %d, len %zu", src_eid, msg_tag,
		len);
	LOG_HEXDUMP_INF(msg, len, "mctp rx message");
	if (len < 1) {
		LOG_ERR("MCTP Message should contain a message type and integrity check byte!");
		return;
	}

	// TODO figure out who owns `msg`!
	LOG_WRN("Are we in ISR? %d", k_is_in_isr());
	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = msg;

	/* If the message endpoint ID matches our local endpoint ID, and its a pldm message, call
	 * the pldm_rx_message call
	 */
	if ((msg_buf[0] & MCTP_MESSAGE_TYPE_MASK) == PLDM_MCTP_MESSAGE_TYPE) {
		rx_msg_work.data = &msg_buf[1];
		rx_msg_work.len = len - 1;
		rx_msg_work.src_eid = src_eid;
		k_work_submit(&rx_msg_work.work);
		/* HAZARD This is potentially error prone but libpldm provides little help here */
//		struct pldm_msg_hdr *pldm_hdr = (struct pldm_msg_hdr *)&(msg_buf[1]);
//		size_t pldm_msg_body_len = len - (1 + sizeof(struct pldm_msg_hdr));
//		void *pldm_msg_body = &msg_buf[1 + sizeof(struct pldm_msg_hdr)];
//
//		pldm_rx_handler(src_eid, msg, pldm_hdr, pldm_msg_body, pldm_msg_body_len);
	}
}

#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
MCTP_UART_DT_DEFINE(mctp_endpoint, DEVICE_DT_GET(DT_NODELABEL(mctp_serial)));
#elif DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_i2c))
MCTP_I2C_GPIO_TARGET_DT_DEFINE(mctp_endpoint, DT_NODELABEL(mctp_i2c));
#endif

int main(void)
{
	uint8_t eid;

#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
	eid = SERIAL_LOCAL_EID;
#elif DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_i2c))
	eid = mctp_endpoint.endpoint_id;
#endif

	LOG_INF("PLDM Endpoint EID:%d TID:%d on %s\n", eid, LOCAL_TID, CONFIG_BOARD_TARGET);

	LOG_INF("decode_set_tid_req: %d", decode_set_tid_req(NULL, 30, NULL));
	k_work_init(&rx_msg_work.work, pldm_rx_handler);

	mctp_set_alloc_ops(malloc, free, realloc);
	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_register_bus(mctp_ctx, &mctp_endpoint.binding, eid);
	mctp_set_rx_all(mctp_ctx, rx_message, NULL);
#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
	mctp_uart_start_rx(&mctp_endpoint);
#endif

	return 0;
}
