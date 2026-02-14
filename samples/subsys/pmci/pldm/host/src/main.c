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
#include <libpldm/platform.h>
#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_uart.h>
#include <zephyr/pmci/mctp/mctp_i2c_gpio_controller.h>

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

#define MCTP_INTEGRITY_CHECK   0x80
#define MCTP_MESSAGE_TYPE_MASK 0x7F

//struct pldm_compact_numeric_sensor_pdr {
//	struct pldm_pdr_hdr hdr;
//	uint16_t terminus_handle;
//	uint16_t sensor_id;
//	uint16_t entity_type;
//	uint16_t entity_instance;
//	uint16_t container_id;
//	uint8_t sensor_name_length;
//	uint8_t base_unit;
//	int8_t unit_modifier;
//	uint8_t occurrence_rate;
//	bitfield8_t range_field_support;
//	int32_t warning_high;
//	int32_t warning_low;
//	int32_t critical_high;
//	int32_t critical_low;
//	int32_t fatal_high;
//	int32_t fatal_low;
//	uint8_t sensor_name[1];
//} __attribute__((packed));

K_SEM_DEFINE(mctp_rx, 0, 1);

const char *MESSAGE_TYPE_TO_STRING[] = {"Response", "Request", "Reserved", "Async Request Notify"};

const char *COMMAND_TO_STRING[] = {"UNDEFINED",      "SetTID",          "GetTID",
				   "GetPLDMVersion", "GetPLDMTypes", "GetPLDMCommands",
				   "SelectPLDMVersion"};

const int pldm_types_array[] = {PLDM_BASE, PLDM_SMBIOS, PLDM_PLATFORM, PLDM_BIOS, PLDM_FRU,
				PLDM_FWUP, PLDM_RDE, PLDM_FILE, PLDM_OEM};
const char *PLDM_TYPE_TO_STRING[] = {"Base", "SMBIOS", "Platform", "BIOS", "FRU", "FWUP", "RDE",
			    "File", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved",
			    "Reserved", "Reserved", "OEM"};

const int pldm_base_commands_array[] = {PLDM_SET_TID, PLDM_GET_TID, PLDM_GET_PLDM_VERSION, PLDM_GET_PLDM_TYPES,
			      PLDM_GET_PLDM_COMMANDS, PLDM_SELECT_PLDM_VERSION,
			      PLDM_NEGOTIATE_TRANSFER_PARAMETERS, PLDM_MULTIPART_SEND,
			      PLDM_MULTIPART_RECEIVE, PLDM_GET_MULTIPART_TRANSFER_SUPPORT};
const char *PLDM_BASE_COMMAND_TO_STRING[] = {"SetTID", "GetTID", "GetPLDMVersion", "GetPLDMTypes",
			      "GetPLDMCommands", "SelectPLDMVersion",
			      "NegotiateTransferParameters", "MultipartSend",
			      "MultipartReceive", "GetMultipartTransferSupport"};

const int pldm_platform_commands_array[] = {PLDM_GET_TERMINUS_UID, PLDM_SET_EVENT_RECEIVER,
				 PLDM_GET_EVENT_RECEIVER, PLDM_PLATFORM_EVENT_MESSAGE,
				 PLDM_POLL_FOR_PLATFORM_EVENT_MESSAGE, PLDM_EVENT_MESSAGE_SUPPORTED,
				 PLDM_EVENT_MESSAGE_BUFFER_SIZE, PLDM_SET_NUMERIC_SENSOR_ENABLE,
				 PLDM_GET_SENSOR_READING, PLDM_GET_SENSOR_THRESHOLDS,
				 PLDM_SET_SENSOR_THRESHOLDS, PLDM_RESTORE_SENSOR_THRESHOLDS,
				 PLDM_GET_SENSOR_HYSTERESIS, PLDM_SET_SENSOR_HYSTERESIS,
				 PLDM_INIT_NUMERIC_SENSOR, PLDM_SET_STATE_SENSOR_ENABLES,
				 PLDM_GET_STATE_SENSOR_READINGS, PLDM_INIT_STATE_SENSOR,
				 PLDM_SET_NUMERIC_EFFECTER_ENABLE, PLDM_SET_NUMERIC_EFFECTER_VALUE,
				 PLDM_GET_NUMERIC_EFFECTER_VALUE, PLDM_SET_STATE_EFFECTER_ENABLES,
				 PLDM_SET_STATE_EFFECTER_STATES, PLDM_GET_STATE_EFFECTER_STATES,
				 PLDM_GET_PLDM_EVENT_LOG_INFO, PLDM_ENABLE_PLDM_EVENT_LOGGING,
				 PLDM_CLEAR_PLDM_EVENT_LOG, PLDM_GET_PLDM_EVENT_LOG_TIMESTAMP,
				 PLDM_SET_PLDM_EVENT_LOG_TIMESTAMP, PLDM_READ_PLDM_EVENT_LOG,
				 PLDM_GET_PLDM_EVENT_LOG_POLICY_INFO, PLDM_SET_PLDM_EVENT_LOG_POLICY,
				 PLDM_FIND_PLDM_EVENT_LOG_ENTRY, PLDM_GET_PDR_REPOSITORY_INFO,
				 PLDM_GET_PDR, PLDM_FIND_PDR, PLDM_RUN_INIT_AGENT,
				 PLDM_GET_PDR_REPOSITORY_SIGNATURE
};

const char *PLDM_PLATFORM_COMMAND_TO_STRING[] = {"GetTerminusUID", "SetEventReceiver",
				 "GetEventReceiver", "PlatformEventMessage",
				 "PollForPlatformEventMessage", "EventMessageSupported",
				 "EventMessageBufferSize", "SetNumericSensorEnable",
				 "GetSensorReading", "GetSensorThresholds",
				 "SetSensorThresholds", "RestoreSensorThresholds",
				 "GetSensorHysteresis", "SetSensorHysteresis", "InitNumericSensor",
				 "SetStateSensorEnables", "GetStateSensorReadings",
				 "InitStateSensor", "SetNumericEffecterEnable",
				 "SetNumericEffecterValue", "GetNumericEffecterValue",
				 "SetStateEffecterEnables", "SetStateEffecterStates",
				 "GetStateEffecterStates", "GetPLDMEventLogInfo",
				 "EnablePLDMEventLogging", "ClearPLDMEventLog",
				 "GetPLDMEventLogTimestamp", "SetPLDMEventLogTimestamp",
				 "ReadPLDMEventLog", "GetPLDMEventLogPolicyInfo",
				 "SetPLDMEventLogPolicy", "FindPLDMEventLogEntry",
				 "GetPDRRepositoryInfo", "GetPDR", "FindPDR", "RunInitAgent",
				 "GetPDRRepositorySignature"
};

const int supported_pldm_types_array[] = {PLDM_BASE, PLDM_PLATFORM};
const char *SUPPORTED_TYPE_TO_STRING[] = {"Base", "Platform"};

const int supported_platform_commands_array[] = {PLDM_GET_SENSOR_READING,
						 PLDM_GET_PDR_REPOSITORY_INFO, PLDM_GET_PDR};

struct mctp_endpoint {
	uint8_t eid;
	struct mctp *mctp_ctx;
};

struct pldm_type_info {
	ver32_t version;
	uint8_t commands[32];
};

struct pldm_tid_info {
	uint8_t tid;
	uint8_t types[8]; /* PLDM Types supported, up to 256 types are representable */
	struct pldm_type_info
		*type_infos; /* An array to be allocated once the types are known... */
};

/* Response message buffer */
uint8_t mctp_msg[256];

/**
 * response data
 */
static uint8_t comp_code;
static uint8_t tid;
static uint8_t types[8];
static uint8_t commands[32];
static ver32_t version;
enum pldm_supported_types expecting_type;
struct pldm_compact_numeric_sensor_pdr sensor_pdr;

/* Discovery if and what a MCTP endpoint can do */
/* TODO pldm_discovery(struct mctp *mctp_ctx, uint8_t eid, struct pldm_tid_info *tid_info); */

static bool is_bit_set(bitfield8_t *bitfield, uint32_t bit)
{
	int byte_idx = bit / 8;
	int bit_idx = bit % 8;

	return IS_BIT_SET(bitfield[byte_idx].byte, bit_idx);
}

static void print_supported_commands(bitfield8_t *commands)
{
	int i;

	LOG_INF("Supported PLDM Commands for type %s:", PLDM_TYPE_TO_STRING[expecting_type]);

	if (expecting_type == PLDM_BASE) {
		for (i = 0; i < ARRAY_SIZE(pldm_base_commands_array); i++) {
			if (is_bit_set(commands, pldm_base_commands_array[i])) {
				LOG_INF(" - %s", PLDM_BASE_COMMAND_TO_STRING[i]);
			}
		}
	} else if (expecting_type == PLDM_PLATFORM) {
		for (i = 0; i < ARRAY_SIZE(pldm_platform_commands_array); i++) {
			if (is_bit_set(commands, pldm_platform_commands_array[i])) {
				LOG_INF(" - %s", PLDM_PLATFORM_COMMAND_TO_STRING[i]);
			}
		}
	}
}

static void print_supported_types(bitfield8_t *types)
{
	int i;

	LOG_INF("Supported PLDM Types:");

	for (i = 0; i < ARRAY_SIZE(pldm_types_array); i++) {
		if (is_bit_set(types, pldm_types_array[i])) {
			LOG_INF(" - %s", PLDM_TYPE_TO_STRING[pldm_types_array[i]]);
		}
	}
}

static void pldm_rx_handler(uint8_t src_eid, void *data, void *msg, size_t msg_len)
{
	struct pldm_header_info hdr_info;
	const char *msg_type_str = "";
	const char *command_str = "";
	int rc;

	rc = unpack_pldm_header(msg, &hdr_info);
	if (rc != 0) {
		LOG_ERR("Failed unpacking pldm header");
	}

	if (hdr_info.msg_type < ARRAY_SIZE(MESSAGE_TYPE_TO_STRING)) {
		msg_type_str = MESSAGE_TYPE_TO_STRING[hdr_info.msg_type];
	}

	if (hdr_info.command < ARRAY_SIZE(COMMAND_TO_STRING)) {
		command_str = COMMAND_TO_STRING[hdr_info.command];
	}

	LOG_INF("received pldm message from mctp endpoint %d len %zu message type %d (%s) command "
		"%d (%s)",
		src_eid, msg_len, hdr_info.msg_type, msg_type_str, hdr_info.command, command_str);

	/* Handle the GetTID Response */
	if (hdr_info.command == PLDM_GET_TID && hdr_info.msg_type == PLDM_RESPONSE) {
		decode_get_tid_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code, &tid);
		LOG_INF("get tid response, completion code %d, tid %d", comp_code, tid);
	} else if (hdr_info.command == PLDM_GET_PLDM_TYPES && hdr_info.msg_type == PLDM_RESPONSE) {
		decode_get_types_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
				      (bitfield8_t *)types);
		LOG_INF("get types response, completion code %d", comp_code);
		LOG_HEXDUMP_INF(types, sizeof(types), "types supported");
		print_supported_types((bitfield8_t *)types);
	} else if (hdr_info.command == PLDM_GET_PLDM_COMMANDS && hdr_info.msg_type == PLDM_RESPONSE) {
		decode_get_commands_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
					 (bitfield8_t *)commands);
		LOG_INF("get commands response, completion code %d", comp_code);
		LOG_HEXDUMP_INF(commands, sizeof(commands), "commands supported");
		print_supported_commands((bitfield8_t *)commands);
	} else if (hdr_info.command == PLDM_GET_PLDM_VERSION && hdr_info.msg_type == PLDM_RESPONSE) {
		/* ignored, we only accept the first version response... */
		uint32_t next_transfer_handle;
		/* ignored */
		uint8_t transfer_flag;

		decode_get_version_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
			&next_transfer_handle, &transfer_flag, &version);

		LOG_INF("get version response, completion code %d, version %d.%d", comp_code,
			version.major, version.minor);
	} else if (hdr_info.command == PLDM_GET_PDR && hdr_info.msg_type == PLDM_RESPONSE) {
		uint32_t next_record_handle;
		uint32_t next_data_transfer_handle;
		uint8_t transfer_flag;
		uint16_t resp_cnt;
		uint8_t record_data[128];
		uint8_t transfer_crc;
		struct pldm_pdr_hdr *pdr_hdr = (struct pldm_pdr_hdr *)record_data;

		decode_get_pdr_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
				    &next_record_handle, &next_data_transfer_handle, &transfer_flag,
				    &resp_cnt, record_data, sizeof(record_data), &transfer_crc);

		LOG_INF("get pdr response, completion code %d, next record handle %d, next data transfer "
			"handle %d, transfer flag %d, record count %d, transfer crc %d",
			comp_code, next_record_handle, next_data_transfer_handle, transfer_flag,
			resp_cnt, transfer_crc);
		LOG_HEXDUMP_INF(record_data, resp_cnt, "pdr record data");

		if (pdr_hdr->type != PLDM_COMPACT_NUMERIC_SENSOR_PDR) {
			LOG_WRN("Received PDR record with unexpected type %d, expected %d",
				pdr_hdr->type, PLDM_COMPACT_NUMERIC_SENSOR_PDR);
		} else if (resp_cnt < sizeof(struct pldm_compact_numeric_sensor_pdr)) {
			LOG_WRN("Received PDR record with insufficient data length %d, expected at least %zu",
				resp_cnt, sizeof(struct pldm_compact_numeric_sensor_pdr));
		} else {
			struct pldm_compact_numeric_sensor_pdr *compact_sensor_pdr =
				(struct pldm_compact_numeric_sensor_pdr *)record_data;

			LOG_INF("Parsed Compact Numeric Sensor PDR: terminus handle %d, sensor id %d, entity "
				"type %d, entity instance %d, container id %d, sensor name length %d, "
				"base unit %d, unit modifier %d, occurrence rate %d, range field support "
				"%d, warning high %d, warning low %d, critical high %d, critical low %d, "
				"fatal high %d, fatal low %d, sensor name %.*s",
				compact_sensor_pdr->terminus_handle, compact_sensor_pdr->sensor_id,
				compact_sensor_pdr->entity_type, compact_sensor_pdr->entity_instance,
				compact_sensor_pdr->container_id, compact_sensor_pdr->sensor_name_length,
				compact_sensor_pdr->base_unit, compact_sensor_pdr->unit_modifier,
				compact_sensor_pdr->occurrence_rate,
				compact_sensor_pdr->range_field_support.byte,
				compact_sensor_pdr->warning_high, compact_sensor_pdr->warning_low,
				compact_sensor_pdr->critical_high, compact_sensor_pdr->critical_low,
				compact_sensor_pdr->fatal_high, compact_sensor_pdr->fatal_low,
				compact_sensor_pdr->sensor_name_length, compact_sensor_pdr->sensor_name);

			sensor_pdr = *compact_sensor_pdr;
		}
	} else if (hdr_info.command == PLDM_GET_SENSOR_READING && hdr_info.msg_type == PLDM_RESPONSE) {
		uint8_t sensor_data_size;
		uint8_t sensor_operation_state;
		uint8_t sensor_event_message_enable;
		uint8_t present_state;
		uint8_t previous_state;
		uint8_t event_state;
		int32_t reading;

		decode_get_sensor_reading_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
					      &sensor_data_size, &sensor_operation_state,
					      &sensor_event_message_enable, &present_state,
					      &previous_state, &event_state, &reading);

		LOG_INF("get sensor reading response, completion code %d, sensor data size %d, "
			"sensor operation state %d, sensor event message enable %d, present state %d, "
			"previous state %d, event state %d, reading %d",
			comp_code, sensor_data_size, sensor_operation_state,
			sensor_event_message_enable, present_state, previous_state, event_state,
			reading);

		if (present_state != PLDM_SENSOR_NORMAL) {
			LOG_WRN("Sensor is in non-normal present state %d", present_state);
			return;
		}

		LOG_INF("Sensor reading is %.2f degrees %s",
				reading * pow(10, sensor_pdr.unit_modifier),
				sensor_pdr.base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ? "C" : "F");

	} else {
		LOG_WRN("unhandled message command %d and type %d", hdr_info.command,
			hdr_info.msg_type);
	}
}

static void rx_message(uint8_t src_eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	LOG_INF("received message from mctp endpoint %d, msg_tag %d, len %zu", src_eid, msg_tag,
		len);
	LOG_HEXDUMP_INF(msg, len, "mctp rx message");

	if (len < 1) {
		LOG_ERR("MCTP Message should contain a message type and integrity check"
			" byte!");
		return;
	}

	/* Treat data as a buffer for byte wise access */
	uint8_t *msg_buf = msg;

	/* if the message endpoint id matches our local endpoint id, and its a pldm message, call
	 * the pldm_rx_message call
	 */
	if ((msg_buf[0] & MCTP_MESSAGE_TYPE_MASK) == PLDM_MCTP_MESSAGE_TYPE) {
		pldm_rx_handler(src_eid, data, &msg_buf[1], len - 1);
	}

	LOG_WRN("Are we in ISR? %d", k_is_in_isr());

	k_sem_give(&mctp_rx);
}

#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
MCTP_UART_DT_DEFINE(mctp_host_serial, DEVICE_DT_GET(DT_NODELABEL(mctp_serial)));

struct mctp_endpoint init_mctp_uart(struct mctp_binding_uart *uart)
{
	struct mctp_endpoint endpoint;

	endpoint.mctp_ctx = mctp_init();
	if (endpoint.mctp_ctx == NULL) {
		LOG_ERR("Failed to initialize MCTP context");
		return endpoint;
	}

	mctp_register_bus(endpoint.mctp_ctx, &uart->binding, LOCAL_EID);
	mctp_set_rx_all(endpoint.mctp_ctx, rx_message, NULL);
	mctp_uart_start_rx(uart);

	endpoint.eid = SERIAL_REMOTE_EID;

	return endpoint;
}
#endif

#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_i2c))
MCTP_I2C_GPIO_CONTROLLER_DT_DEFINE(mctp_i2c_gpio_ctrl, DT_NODELABEL(mctp_i2c));

struct mctp_endpoint init_mctp_i2c_gpio(struct mctp_binding_i2c_gpio_controller *i2c_gpio)
{
	struct mctp_endpoint endpoint;

	endpoint.mctp_ctx = mctp_init();
	if (endpoint.mctp_ctx == NULL) {
		LOG_ERR("Failed to initialize MCTP context");
		return endpoint;
	}

	mctp_register_bus(endpoint.mctp_ctx, &i2c_gpio->binding, LOCAL_EID);
	mctp_set_rx_all(endpoint.mctp_ctx, rx_message, NULL);

	endpoint.eid = i2c_gpio->endpoint_ids[0];

	return endpoint;
}
#endif

void pdlm_discovery(struct mctp *mctp_ctx, uint8_t eid)
{
	LOG_INF("Starting PLDM discovery on MCTP EID %d", eid);
	/* TODO implement discovery */
	int i, j, rc;

	/* PLDM message is after the MCTP message type byte */
	struct pldm_msg *msg = &mctp_msg[1];
	uint32_t instance = 0;

	/* GetTID request/response */
	uint8_t get_tid_request_size = PLDM_MSG_SIZE(0) + 1;

	encode_get_tid_req(instance, msg);
	instance++;

	LOG_HEXDUMP_INF(mctp_msg, get_tid_request_size, "pldm get_tid_request");
	rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
			     get_tid_request_size);
	if (rc != 0) {
		LOG_WRN("Failed to send message, errno %d\n", rc);
		return;
	} else {
		rc = k_sem_take(&mctp_rx, K_MSEC(1000));
		if (rc == -EAGAIN) {
			LOG_WRN("Timeout waiting for get tid response");
			return;
		}
	}
	uint8_t get_types_request_size = PLDM_MSG_SIZE(0) + 1;

	/* GetPLDMTypes request/response */
	memset(types, 0, sizeof(types));

	encode_get_types_req(instance, msg);
	instance++;

	LOG_HEXDUMP_INF(mctp_msg, get_types_request_size, "pldm get_types_request");
	rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
			     get_types_request_size);
	if (rc != 0) {
		LOG_WRN("Failed to send message, errno %d\n", rc);
		return;
	} else {
		rc = k_sem_take(&mctp_rx, K_MSEC(1000));
		if (rc == -EAGAIN) {
			LOG_WRN("Timeout waiting for get types response");
			return;
		}
	}

	/* TODO in the discovery case we'd iterate types to gather information on versions
	 * and available commands for each version (or a selected version)
	 */

	for (i = 0; i < ARRAY_SIZE(supported_pldm_types_array) ; i++) {
		printk("type %d\n", supported_pldm_types_array[i]);
	
		if (!is_bit_set(types, supported_pldm_types_array[i])) {
			printk("type %s not supported, skipping\n", SUPPORTED_TYPE_TO_STRING[i]);
			continue;
		}
		uint8_t pldm_type = supported_pldm_types_array[i];
		expecting_type = pldm_type;

		printk("Getting version and commands for type %s\n", SUPPORTED_TYPE_TO_STRING[i]);
		/* GetPLDMVersion request/response */
		uint32_t transfer_handle = 0;
		uint8_t transfer_opflag = PLDM_GET_FIRSTPART;
		uint8_t get_version_request_size = PLDM_MSG_SIZE(PLDM_GET_VERSION_REQ_BYTES) + 1;

		encode_get_version_req(instance, transfer_handle, transfer_opflag, pldm_type, msg);
		instance++;

		LOG_HEXDUMP_INF(mctp_msg, get_version_request_size, "pldm get_version_request");
		rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
				     get_version_request_size);
		if (rc != 0) {
			LOG_WRN("Failed to send message, errno %d\n", rc);
			return;
		} else {
			rc = k_sem_take(&mctp_rx, K_MSEC(1000));
			if (rc == -EAGAIN) {
				LOG_WRN("Timeout waiting for get version response");
				return;
			}
		}

		/* GetPLDMCommands request/response */
		uint8_t get_commands_request_size = PLDM_MSG_SIZE(PLDM_GET_COMMANDS_REQ_BYTES) + 1;

		encode_get_commands_req(instance, pldm_type, version, msg);
		instance++;

		LOG_HEXDUMP_INF(mctp_msg, get_commands_request_size, "pldm get_commands_request");
		rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
				     get_commands_request_size);
		if (rc != 0) {
			LOG_WRN("Failed to send message, errno %d\n", rc);
			return;
		} else {
			rc = k_sem_take(&mctp_rx, K_MSEC(1000));
			if (rc == -EAGAIN) {
				LOG_WRN("Timeout waiting for get commands response");
				return;
			}
		}

		/* If commands supported include GetPDR, let's get the first one */
		if (is_bit_set(commands, PLDM_GET_PDR)) {
			uint8_t get_pdr_request_size = PLDM_MSG_SIZE(PLDM_GET_PDR_REQ_BYTES) + 1;
			uint32_t record_handle = 0;
			uint32_t data_transfer_handle = 0;
			uint8_t transfer_opflag = PLDM_GET_FIRSTPART;
			uint16_t request_cnt = 128;
			uint16_t record_chg_num = 0;

			encode_get_pdr_req(instance, record_handle, data_transfer_handle, transfer_opflag,
					   request_cnt, record_chg_num, msg, PLDM_GET_PDR_REQ_BYTES);
			instance++;

			LOG_HEXDUMP_INF(mctp_msg, get_pdr_request_size, "pldm get_pdr_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
						     get_pdr_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d\n", rc);
				return;
			} else {
				rc = k_sem_take(&mctp_rx, K_MSEC(1000));
				if (rc == -EAGAIN) {
					LOG_WRN("Timeout waiting for get pdr response");
					return;
				}
			}
		}

		/* If first PDR is a temperature sensor, get the reading */
		if (sensor_pdr.base_unit == PLDM_SENSOR_UNIT_DEGRESS_C ||
		    sensor_pdr.base_unit == PLDM_SENSOR_UNIT_DEGRESS_F) {
			uint8_t get_sensor_reading_request_size =
				PLDM_MSG_SIZE(PLDM_GET_SENSOR_READING_REQ_BYTES) + 1;
			bool8_t rearm = false;

			encode_get_sensor_reading_req(instance, sensor_pdr.sensor_id, rearm, msg);
			instance++;

			LOG_HEXDUMP_INF(mctp_msg, get_sensor_reading_request_size,
					 "pldm get_sensor_reading_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
						     get_sensor_reading_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d\n", rc);
				return;
			} else {
				rc = k_sem_take(&mctp_rx, K_MSEC(1000));
				if (rc == -EAGAIN) {
					LOG_WRN("Timeout waiting for get sensor reading response");
					return;
				}
			}
		}
	}
}

int main(void)
{
	int rc, i;

	LOG_INF("PLDM Host EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	mctp_set_alloc_ops(malloc, free, realloc);
	struct mctp_endpoint endpoints[] = {
#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
		init_mctp_uart(&mctp_host_serial),
#endif
#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_i2c))
		init_mctp_i2c_gpio(&mctp_i2c_gpio_ctrl),
#endif
	};

	/* We can set this one time here */
	mctp_msg[0] = PLDM_MCTP_MESSAGE_TYPE;

	/* Loop over MCTP endpoints and do PLDM discovery on them, sending a sequence of
	 * commands and waiting on responses */
	for (i = 0; i < ARRAY_SIZE(endpoints); i++) {
		if (endpoints[i].mctp_ctx != NULL) {
			pdlm_discovery(endpoints[i].mctp_ctx, endpoints[i].eid);
		}
	}


	return 0;
}
