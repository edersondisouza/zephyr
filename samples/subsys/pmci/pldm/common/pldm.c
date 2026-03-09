#include <zephyr/kernel.h>

#include <libpldm/edac.h>

#include "pldm.h"

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(pldm, CONFIG_MCTP_LOG_LEVEL);

#define PLDM_MCTP_MESSAGE_TYPE 1

static const int pldm_types_array[] = {PLDM_BASE, PLDM_SMBIOS, PLDM_PLATFORM, PLDM_BIOS, PLDM_FRU,
				       PLDM_FWUP, PLDM_RDE, PLDM_FILE, PLDM_OEM};
static const char *PLDM_TYPE_TO_STRING[] = {"Base", "SMBIOS", "Platform", "BIOS", "FRU", "FWUP",
					    "RDE", "File", "Reserved", "Reserved", "Reserved",
					    "Reserved", "Reserved", "Reserved", "Reserved", "OEM"};

static const int pldm_base_commands_array[] = {PLDM_SET_TID, PLDM_GET_TID, PLDM_GET_PLDM_VERSION,
					       PLDM_GET_PLDM_TYPES, PLDM_GET_PLDM_COMMANDS,
					       PLDM_SELECT_PLDM_VERSION,
					       PLDM_NEGOTIATE_TRANSFER_PARAMETERS,
					       PLDM_MULTIPART_SEND, PLDM_MULTIPART_RECEIVE,
					       PLDM_GET_MULTIPART_TRANSFER_SUPPORT};

static const char *PLDM_BASE_COMMAND_TO_STRING[] = {"SetTID", "GetTID", "GetPLDMVersion",
						    "GetPLDMTypes", "GetPLDMCommands",
						    "SelectPLDMVersion",
						    "NegotiateTransferParameters", "MultipartSend",
						    "MultipartReceive",
						    "GetMultipartTransferSupport"};

static const int pldm_platform_commands_array[] = {PLDM_GET_TERMINUS_UID, PLDM_SET_EVENT_RECEIVER,
						   PLDM_GET_EVENT_RECEIVER,
						   PLDM_PLATFORM_EVENT_MESSAGE,
						   PLDM_POLL_FOR_PLATFORM_EVENT_MESSAGE,
						   PLDM_EVENT_MESSAGE_SUPPORTED,
						   PLDM_EVENT_MESSAGE_BUFFER_SIZE,
						   PLDM_SET_NUMERIC_SENSOR_ENABLE,
						   PLDM_GET_SENSOR_READING,
						   PLDM_GET_SENSOR_THRESHOLDS,
						   PLDM_SET_SENSOR_THRESHOLDS,
						   PLDM_RESTORE_SENSOR_THRESHOLDS,
						   PLDM_GET_SENSOR_HYSTERESIS,
						   PLDM_SET_SENSOR_HYSTERESIS,
						   PLDM_INIT_NUMERIC_SENSOR,
						   PLDM_SET_STATE_SENSOR_ENABLES,
						   PLDM_GET_STATE_SENSOR_READINGS,
						   PLDM_INIT_STATE_SENSOR,
						   PLDM_SET_NUMERIC_EFFECTER_ENABLE,
						   PLDM_SET_NUMERIC_EFFECTER_VALUE,
						   PLDM_GET_NUMERIC_EFFECTER_VALUE,
						   PLDM_SET_STATE_EFFECTER_ENABLES,
						   PLDM_SET_STATE_EFFECTER_STATES,
						   PLDM_GET_STATE_EFFECTER_STATES,
						   PLDM_GET_PLDM_EVENT_LOG_INFO,
						   PLDM_ENABLE_PLDM_EVENT_LOGGING,
						   PLDM_CLEAR_PLDM_EVENT_LOG,
						   PLDM_GET_PLDM_EVENT_LOG_TIMESTAMP,
						   PLDM_SET_PLDM_EVENT_LOG_TIMESTAMP,
						   PLDM_READ_PLDM_EVENT_LOG,
						   PLDM_GET_PLDM_EVENT_LOG_POLICY_INFO,
						   PLDM_SET_PLDM_EVENT_LOG_POLICY,
						   PLDM_FIND_PLDM_EVENT_LOG_ENTRY,
						   PLDM_GET_PDR_REPOSITORY_INFO,
						   PLDM_GET_PDR, PLDM_FIND_PDR, PLDM_RUN_INIT_AGENT,
		  				   PLDM_GET_PDR_REPOSITORY_SIGNATURE
};

static const char *PLDM_PLATFORM_COMMAND_TO_STRING[] = {"GetTerminusUID", "SetEventReceiver",
							"GetEventReceiver", "PlatformEventMessage",
							"PollForPlatformEventMessage",
							"EventMessageSupported",
							"EventMessageBufferSize",
							"SetNumericSensorEnable",
							"GetSensorReading", "GetSensorThresholds",
							"SetSensorThresholds",
							"RestoreSensorThresholds",
							"GetSensorHysteresis",
							"SetSensorHysteresis", "InitNumericSensor",
							"SetStateSensorEnables",
							"GetStateSensorReadings", "InitStateSensor",
							"SetNumericEffecterEnable",
							"SetNumericEffecterValue",
							"GetNumericEffecterValue",
							"SetStateEffecterEnables",
							"SetStateEffecterStates",
							"GetStateEffecterStates",
							"GetPLDMEventLogInfo",
							"EnablePLDMEventLogging",
							"ClearPLDMEventLog",
							"GetPLDMEventLogTimestamp",
							"SetPLDMEventLogTimestamp",
							"ReadPLDMEventLog",
							"GetPLDMEventLogPolicyInfo",
							"SetPLDMEventLogPolicy",
							"FindPLDMEventLogEntry",
							"GetPDRRepositoryInfo", "GetPDR", "FindPDR",
							"RunInitAgent", "GetPDRRepositorySignature"
};

enum pldm_discovery_state {
	PLDM_DISCOVERY_IDLE,
	PLDM_DISCOVERY_GET_TID,
	PLDM_DISCOVERY_GET_TYPES,
	PLDM_DISCOVERY_GET_VERSION,
	PLDM_DISCOVERY_GET_COMMANDS,
	PLDM_DISCOVERY_COMPLETE
};

static enum pldm_discovery_state state = PLDM_DISCOVERY_IDLE;
static int current_type;

/* Response message buffer */
static uint8_t mctp_msg[256] = { PLDM_MCTP_MESSAGE_TYPE };

static struct pldm_tid_info tid_info;
static uint32_t instance = 0;
static uint8_t comp_code;

static uint8_t *out_buf;
static size_t *out_buf_size;
static uint8_t *sensor_present_state;

K_SEM_DEFINE(mctp_rx, 0, 1);

void log_commands(enum pldm_supported_types type, bitfield8_t *commands)
{
	int i;

	LOG_INF("Supported PLDM Commands for type %s:", PLDM_TYPE_TO_STRING[type]);

	if (type == PLDM_BASE) {
		for (i = 0; i < ARRAY_SIZE(pldm_base_commands_array); i++) {
			if (is_bit_set(commands, pldm_base_commands_array[i])) {
				LOG_INF(" - %s", PLDM_BASE_COMMAND_TO_STRING[i]);
			}
		}
	} else if (type == PLDM_PLATFORM) {
		for (i = 0; i < ARRAY_SIZE(pldm_platform_commands_array); i++) {
			if (is_bit_set(commands, pldm_platform_commands_array[i])) {
				LOG_INF(" - %s", PLDM_PLATFORM_COMMAND_TO_STRING[i]);
			}
		}
	} else {
		LOG_INF(" - (command names not logged for this type)");
		for (i = 0; i < 256; i++) {
			if (is_bit_set(commands, i)) {
				LOG_INF(" - Command number 0x%0x", i);
			}
		}
	}
}

void log_types(bitfield8_t *types)
{
	int i;

	LOG_INF("Supported PLDM Types:");

	for (i = 0; i < ARRAY_SIZE(pldm_types_array); i++) {
		if (is_bit_set(types, pldm_types_array[i])) {
			LOG_INF(" - %s", PLDM_TYPE_TO_STRING[pldm_types_array[i]]);
		}
	}
}

static void inc_instance(void)
{
	instance++;
	if (instance > PLDM_INSTANCE_MAX) {
		instance = 0;
	}
}

void pldm_response_handler(struct pldm_msg *msg, size_t msg_len)
{
	struct pldm_header_info hdr_info;
	int rc;

	LOG_HEXDUMP_DBG(msg, msg_len, "Received PLDM message");

	comp_code = PLDM_ERROR;

	rc = unpack_pldm_header((struct pldm_msg_hdr *)msg, &hdr_info);
	if (rc != 0) {
		LOG_WRN("Failed unpacking pldm header");
		goto out;
	}

	LOG_DBG("Handling PLDM message type 0x%x command 0x%x", hdr_info.msg_type,
		hdr_info.command);

	if (hdr_info.msg_type != PLDM_RESPONSE) {
		LOG_WRN("Received PLDM message with unsupported message type %d, expected response",
			hdr_info.msg_type);
		state = PLDM_DISCOVERY_IDLE;
		goto out;
	}

	/* Handle the GetTID Response */
	switch (hdr_info.command) {
	case PLDM_GET_TID:
		if (state != PLDM_DISCOVERY_GET_TID) {
			LOG_INF("Received GetTID response while not in the correct state for discovery, ignoring");
			goto out;
		}
		rc = decode_get_tid_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code, &tid_info.tid);
		if (rc != 0) {
			LOG_INF("Failed to decode get tid response %d", rc);
			comp_code = rc;
			goto out;
		}

		LOG_DBG("GetTID response, completion code %d, tid %d", comp_code, tid_info.tid);
		break;

	case PLDM_GET_PLDM_TYPES:
		if (state != PLDM_DISCOVERY_GET_TYPES) {
			LOG_INF("Received GetPLDMTypes response while not in the correct state for discovery, ignoring");
			goto out;
		}
		rc = decode_get_types_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
				      (bitfield8_t *)&tid_info.types);
		if (rc != 0) {
			LOG_INF("Failed to decode get types response %d", rc);
			comp_code = rc;
			goto out;
		}

		LOG_DBG("GetPLDMTypes response, completion code %d", comp_code);
		LOG_HEXDUMP_DBG(tid_info.types, sizeof(tid_info.types), "types supported");
		break;

	case PLDM_GET_PLDM_COMMANDS:
		if (state != PLDM_DISCOVERY_GET_COMMANDS) {
			LOG_INF("Received GetPLDMCommands response while not in the correct state for discovery, ignoring");
			goto out;
		}
		rc = decode_get_commands_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
					 (bitfield8_t *)&tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].commands);
		if (rc != 0) {
			LOG_INF("Failed to decode get commands response %d", rc);
			comp_code = rc;
			goto out;
		}

		LOG_DBG("GetPLDMCommands response, completion code %d", comp_code);
		LOG_HEXDUMP_DBG(tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].commands,
			      sizeof(tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].commands),
			      "raw commands response");
		break;

	case PLDM_GET_PLDM_VERSION: {
		if (state != PLDM_DISCOVERY_GET_VERSION) {
			LOG_INF("Received GetPLDMVersion response while not in the correct state for discovery, ignoring");
			goto out;
		}
		/* ignored, we only accept the first version response... */
		uint32_t next_transfer_handle;
		/* ignored */
		uint8_t transfer_flag;

		rc = decode_get_version_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
			&next_transfer_handle, &transfer_flag, &tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].version);
		if (rc != 0) {
			LOG_INF("Failed to decode get version response %d", rc);
			comp_code = rc;
			goto out;
		}

		LOG_DBG("GetPLDMVersion response, completion code %d, version %d.%d", comp_code,
			 tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].version.major,
			 tid_info.type_infos[PLDM_TYPE_INFO_IDX(current_type)].version.minor);

		break;
	}
	case PLDM_GET_PDR: {
		uint32_t next_record_handle;
		uint32_t next_data_transfer_handle;
		uint8_t transfer_flag;
		uint16_t resp_cnt;
		uint8_t transfer_crc;

		rc = decode_get_pdr_resp(msg, msg_len - sizeof(struct pldm_msg_hdr), &comp_code,
				    &next_record_handle, &next_data_transfer_handle, &transfer_flag,
				    &resp_cnt, out_buf, *out_buf_size, &transfer_crc);
		if (rc != 0) {
			LOG_INF("Failed to decode get pdr response %d", rc);
			comp_code = rc;
			goto out;
		}

		*out_buf_size = resp_cnt;
		LOG_DBG("GetPDR response, completion code %d, next record handle %d, next data "
			"transfer handle %d, transfer flag %d, record count %d, transfer crc %d",
			comp_code, next_record_handle, next_data_transfer_handle, transfer_flag,
			resp_cnt, transfer_crc);
		LOG_HEXDUMP_DBG(out_buf, resp_cnt, "pdr record data");

		break;
	}
	case PLDM_GET_SENSOR_READING: {
		uint8_t sensor_data_size;
		uint8_t sensor_operation_state;
		uint8_t sensor_event_message_enable;
		uint8_t previous_state;
		uint8_t event_state;

		rc = decode_get_sensor_reading_resp(msg, msg_len - sizeof(struct pldm_msg_hdr),
						    &comp_code, &sensor_data_size,
						    &sensor_operation_state,
						    &sensor_event_message_enable,
						    sensor_present_state, &previous_state,
						    &event_state, out_buf);
		if (rc != 0) {
			LOG_INF("Failed to decode get sensor reading response %d", rc);
			comp_code = rc;
			goto out;
		}

		LOG_DBG("GetSensorReading response, completion code %d, sensor data size %d, "
			"sensor operation state %d, sensor event message enable %d, "
			"present state %d, previous state %d, event state %d", comp_code,
			sensor_data_size, sensor_operation_state, sensor_event_message_enable,
			*sensor_present_state, previous_state, event_state);

		switch (sensor_data_size) {
		case PLDM_SENSOR_DATA_SIZE_UINT8:
		case PLDM_SENSOR_DATA_SIZE_SINT8:
			*out_buf_size = sizeof(uint8_t);
			break;
		case PLDM_SENSOR_DATA_SIZE_UINT16:
		case PLDM_SENSOR_DATA_SIZE_SINT16:
			*out_buf_size = sizeof(uint16_t);
			break;
		case PLDM_SENSOR_DATA_SIZE_UINT32:
		case PLDM_SENSOR_DATA_SIZE_SINT32:
			*out_buf_size = sizeof(uint32_t);
		}
		break;
	}
	default:
		LOG_INF("Unhandled message command %d and type %d", hdr_info.command,
			hdr_info.msg_type);
	}

out:
	k_sem_give(&mctp_rx);
}

/* Discover what a MCTP endpoint can do */
int pldm_discovery(struct mctp *mctp_ctx, uint8_t eid, struct pldm_tid_info *out_tid_info)
{
	LOG_INF("Starting PLDM discovery on MCTP EID %d", eid);
	int rc = 0;

	comp_code = 0;

	/* PLDM message is after the MCTP message type byte */
	struct pldm_msg *msg = (struct pldm_msg *)&mctp_msg[1];

	while (state != PLDM_DISCOVERY_COMPLETE) {
		if (comp_code != 0) {
			LOG_WRN("Received PLDM response with error completion code %d, "
				"aborting discovery", comp_code);
			rc = comp_code;
			goto out;
		}

		switch (state) {
		case PLDM_DISCOVERY_IDLE:
			/* GetTID request/response */
			uint8_t get_tid_request_size = PLDM_MSG_SIZE(0) + 1;

			memset(&tid_info, 0, sizeof(struct pldm_tid_info));

			rc = encode_get_tid_req(instance, msg);
			__ASSERT(rc == 0, "Failed to encode get tid request");
			inc_instance();

			state = PLDM_DISCOVERY_GET_TID;
			LOG_HEXDUMP_DBG(mctp_msg, get_tid_request_size, "pldm get_tid_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
					     get_tid_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d", rc);
				goto out;
			}
			break;

		case PLDM_DISCOVERY_GET_TID:
			/* GetPLDMTypes request/response */
			uint8_t get_types_request_size = PLDM_MSG_SIZE(0) + 1;

			rc = encode_get_types_req(instance, msg);
			__ASSERT(rc == 0, "Failed to encode get types request");
			inc_instance();

			state = PLDM_DISCOVERY_GET_TYPES;
			current_type = 0;
			LOG_HEXDUMP_DBG(mctp_msg, get_types_request_size, "pldm get_types_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
					     get_types_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d", rc);
				goto out;
			}
			break;

		case PLDM_DISCOVERY_GET_TYPES:
			/* Find next type to query about */
			while (current_type < (PLDM_OEM + 1) && !is_bit_set(tid_info.types, current_type)) {
				current_type++;

				/* Between PDLM_FILE and PLDM_OEM there are only reserved types */
				if (current_type == PLDM_FILE + 1)
					current_type = PLDM_OEM;
			}
			if (current_type == (PLDM_OEM + 1)) {
				state = PLDM_DISCOVERY_COMPLETE;
				LOG_INF("PLDM Discovery complete!");
				break;
			}

			LOG_DBG("Getting version and commands for type %d", current_type);

			/* GetPLDMVersion request/response */
			uint32_t transfer_handle = 0;
			uint8_t transfer_opflag = PLDM_GET_FIRSTPART;
			uint8_t get_version_request_size = PLDM_MSG_SIZE(PLDM_GET_VERSION_REQ_BYTES) + 1;

			rc = encode_get_version_req(instance, transfer_handle, transfer_opflag, current_type, msg);
			__ASSERT(rc == 0, "Failed to encode get version request");
			inc_instance();

			state = PLDM_DISCOVERY_GET_VERSION;
			LOG_HEXDUMP_DBG(mctp_msg, get_version_request_size, "pldm get_version_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
					     get_version_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d", rc);
				goto out;
			}
			break;

		case PLDM_DISCOVERY_GET_VERSION:
			/* GetPLDMCommands request/response */
			uint8_t get_commands_request_size = PLDM_MSG_SIZE(PLDM_GET_COMMANDS_REQ_BYTES) + 1;

			rc = encode_get_commands_req(instance, current_type, tid_info.type_infos[current_type].version, msg);
			__ASSERT(rc == 0, "Failed to encode get commands request");
			inc_instance();

			LOG_DBG("Getting commands for type %d version %d.%d", current_type,
				 tid_info.type_infos[current_type].version.major,
				 tid_info.type_infos[current_type].version.minor);
			state = PLDM_DISCOVERY_GET_COMMANDS;
			LOG_HEXDUMP_DBG(mctp_msg, get_commands_request_size, "pldm get_commands_request");
			rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
					     get_commands_request_size);
			if (rc != 0) {
				LOG_WRN("Failed to send message, errno %d\n", rc);
				goto out;
			}
			break;

		case PLDM_DISCOVERY_GET_COMMANDS:
			LOG_DBG("Finished getting commands for type %d, moving to next type", current_type);
			current_type++;
			state = PLDM_DISCOVERY_GET_TYPES;
			continue;

		case PLDM_DISCOVERY_COMPLETE:
			/* should never get here since the while condition should prevent it */
			break;
		}

		if (state != PLDM_DISCOVERY_COMPLETE) {
			rc = k_sem_take(&mctp_rx, K_MSEC(1000));
			if (rc == -EAGAIN) {
				LOG_WRN("Timeout waiting for response to PLDM discovery message");
				goto out;
			}
		}
	}

	/* Copy discovered tid info to output */
	if (out_tid_info != NULL) {
		*out_tid_info = tid_info;
		rc = comp_code;
	}

out:
	state = PLDM_DISCOVERY_IDLE;
	return rc;
}

int pldm_get_pdr(struct mctp *mctp_ctx, uint8_t eid, uint16_t record_handle, uint8_t *pdr_buf, size_t *pdr_len)
{
	uint8_t get_pdr_request_size = PLDM_MSG_SIZE(PLDM_GET_PDR_REQ_BYTES) + 1;
	uint32_t data_transfer_handle = 0;
	uint8_t transfer_opflag = PLDM_GET_FIRSTPART;
	uint16_t request_cnt = 128;
	uint16_t record_chg_num = 0;
	int rc;

	/* PLDM message is after the MCTP message type byte */
	struct pldm_msg *msg = (struct pldm_msg *)&mctp_msg[1];

	out_buf = pdr_buf;
	out_buf_size = pdr_len;

	rc = encode_get_pdr_req(instance, record_handle, data_transfer_handle, transfer_opflag,
			   request_cnt, record_chg_num, msg, PLDM_GET_PDR_REQ_BYTES);
	__ASSERT(rc == 0, "Failed to encode get pdr request");
	inc_instance();

	LOG_HEXDUMP_DBG(mctp_msg, get_pdr_request_size, "pldm get_pdr_request");
	rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
				     get_pdr_request_size);
	if (rc != 0) {
		LOG_WRN("Failed to send message, errno %d\n", rc);
		return rc;
	} else {
		rc = k_sem_take(&mctp_rx, K_MSEC(1000));
		if (rc == -EAGAIN) {
			LOG_WRN("Timeout waiting for get pdr response");
			return rc;
		}
	}

	return comp_code;
}

int pldm_get_sensor_reading(struct mctp *mctp_ctx, uint8_t eid, uint16_t sensor_id, void *reading_data, size_t *reading_len, uint8_t *present_state)
{
	uint8_t get_sensor_reading_request_size =
		PLDM_MSG_SIZE(PLDM_GET_SENSOR_READING_REQ_BYTES) + 1;
	bool8_t rearm = false;
	int rc;

	/* PLDM message is after the MCTP message type byte */
	struct pldm_msg *msg = (struct pldm_msg *)&mctp_msg[1];

	out_buf = reading_data;
	out_buf_size = reading_len;
	sensor_present_state = present_state;

	rc = encode_get_sensor_reading_req(instance, sensor_id, rearm, msg);
	__ASSERT(rc == 0, "Failed to encode get sensor reading request");
	inc_instance();

	LOG_HEXDUMP_DBG(mctp_msg, get_sensor_reading_request_size,
			 "pldm get_sensor_reading_request");
	rc = mctp_message_tx(mctp_ctx, eid, false, 0, mctp_msg,
				     get_sensor_reading_request_size);
	if (rc != 0) {
		LOG_WRN("Failed to send message, errno %d\n", rc);
		return rc;
	} else {
		rc = k_sem_take(&mctp_rx, K_MSEC(1000));
		if (rc == -EAGAIN) {
			LOG_WRN("Timeout waiting for get sensor reading response");
			return rc;
		}
	}

	return comp_code;
}

int pldm_request_handler(struct mctp *mctp_ctx, uint8_t src_eid, struct pldm_tid_info *tid_info,
			 struct pldm_pdr_hdr *pdrs[], size_t pdrs_len, struct pldm_commands_cb *cbs,
			 struct pldm_msg *msg, size_t msg_len)
{
	struct pldm_header_info hdr_info;
	uint8_t resp_msg_buf[256] = { PLDM_MCTP_MESSAGE_TYPE };
	struct pldm_msg *resp_msg = (struct pldm_msg *)&resp_msg_buf[1];
	size_t resp_msg_len = 0;
	int rc;

	LOG_HEXDUMP_DBG(msg, msg_len, "Received PLDM message");

	rc = unpack_pldm_header((struct pldm_msg_hdr *)msg, &hdr_info);
	if (rc != 0) {
		LOG_ERR("Failed unpacking pldm header");
	}

	LOG_DBG("Handling PLDM message type 0x%x command 0x%x", hdr_info.msg_type,
		hdr_info.command);

	if (hdr_info.msg_type != PLDM_REQUEST) {
		LOG_WRN("Received PLDM message with unsupported message type %d, expected request",
			hdr_info.msg_type);
		state = PLDM_DISCOVERY_IDLE;
		return -EINVAL;
	}

	/* Handle the GetTID Response */
	switch (hdr_info.command) {
	case PLDM_GET_TID: {
		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_TID_RESP_BYTES) + 1;

		rc = encode_get_tid_resp(instance, PLDM_SUCCESS, tid_info->tid, resp_msg);
		__ASSERT(rc == 0, "Failed to encode get tid response");

		break;
	}
	case PLDM_GET_PLDM_TYPES: {
		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_TYPES_RESP_BYTES) + 1;

		rc = encode_get_types_resp(instance, PLDM_SUCCESS, (bitfield8_t *)tid_info->types,
					   resp_msg);
		__ASSERT(rc == 0, "Failed to encode get types response");

		break;
	}
	case PLDM_GET_PLDM_VERSION: {
		uint32_t transfer_handle;
		uint8_t transfer_opflag;
		uint8_t type;

		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_VERSION_RESP_BYTES) + 1;

		/* First decode request to get the type */
		if (msg_len < PLDM_GET_VERSION_REQ_BYTES) {
			LOG_WRN("Received get version request with invalid length %d, expected at least %d", msg_len, PLDM_GET_VERSION_REQ_BYTES);
			rc = encode_get_version_resp(instance, PLDM_ERROR_INVALID_LENGTH, 0, 0, NULL, 0, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get version response");
			break;
		}

		rc = decode_get_version_req(msg, PLDM_GET_VERSION_REQ_BYTES, &transfer_handle, &transfer_opflag, &type);
		if (rc != 0) {
			LOG_INF("Failed to decode get version request %d", rc);
			rc = encode_get_version_resp(instance, PLDM_ERROR, 0, 0, NULL, 0, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get version response");
			break;
		}

		if (!is_bit_set(tid_info->types, type)) {
			LOG_WRN("Received get version request for unsupported type %d", type);
			rc = encode_get_version_resp(instance,
						     PLDM_GET_PLDM_VERSION_INVALID_PLDM_TYPE_IN_REQUEST_DATA,
						     0, 0, NULL, 0, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get version response");
			break;
		}

		rc = encode_get_version_resp(instance, PLDM_SUCCESS, 0, 0,
					     &tid_info->type_infos[PLDM_TYPE_INFO_IDX(type)].version,
					     sizeof(tid_info->type_infos[PLDM_TYPE_INFO_IDX(type)].version),
					     resp_msg);
		__ASSERT(rc == 0, "Failed to encode get version response");

		break;
	}
	case PLDM_GET_PLDM_COMMANDS: {
		ver32_t version;
		uint8_t type;

		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_COMMANDS_RESP_BYTES) + 1;

		/* First decode request to get the type */
		if (msg_len < PLDM_GET_COMMANDS_REQ_BYTES) {
			LOG_WRN("Received get commands request with invalid length %d, expected at least %d", msg_len, PLDM_GET_COMMANDS_REQ_BYTES);
			rc = encode_get_commands_resp(instance, PLDM_ERROR_INVALID_LENGTH, NULL, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get commands response");
			break;
		}

		rc = decode_get_commands_req(msg, PLDM_GET_COMMANDS_REQ_BYTES, &type, &version);
		if (rc != 0) {
			LOG_INF("Failed to decode get commands request %d", rc);
			rc = encode_get_commands_resp(instance, PLDM_ERROR, NULL, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get commands response");
			break;
		}

		if (!is_bit_set(tid_info->types, type)) {
			LOG_WRN("Received get commands request for unsupported type %d", type);
			rc = encode_get_commands_resp(instance,
						      PLDM_GET_PLDM_COMMANDS_INVALID_PLDM_TYPE_IN_REQUEST_DATA,
						      NULL, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get commands response");
			break;
		}

		if (memcmp(&version, &tid_info->type_infos[PLDM_TYPE_INFO_IDX(type)].version, sizeof(ver32_t)) != 0) {
			LOG_WRN("Received get commands request for unsupported version %d.%d for type %d",
				version.major, version.minor, type);
			rc = encode_get_commands_resp(instance,
						      PLDM_GET_PLDM_COMMANDS_INVALID_PLDM_VERSION_IN_REQUEST_DATA,
						      NULL, resp_msg);
			__ASSERT(rc == 0, "Failed to encode get commands response");
			break;
		}

		rc = encode_get_commands_resp(instance, PLDM_SUCCESS,
					      (bitfield8_t *)tid_info->type_infos[PLDM_TYPE_INFO_IDX(type)].commands,
					      resp_msg);
		__ASSERT(rc == 0, "Failed to encode get commands response");

		break;
	}
	case PLDM_GET_PDR: {
		uint32_t record_handle;
		uint32_t data_transfer_handle;
		uint8_t transfer_opflag;
		uint16_t request_cnt;
		uint16_t record_chg_num;
		uint16_t next_record_handle;

		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_PDR_MIN_RESP_BYTES) + 1;

		/* First decode request to get the request parameters */
		if (msg_len < PLDM_GET_PDR_REQ_BYTES) {
			LOG_WRN("Received get pdr request with invalid length %d, expected at least %d",
				msg_len, PLDM_GET_PDR_REQ_BYTES);
			rc = encode_get_pdr_resp(instance, PLDM_ERROR_INVALID_LENGTH, 0, 0,
						 PLDM_PLATFORM_TRANSFER_START_AND_END, 0, NULL, 0,
						 resp_msg);
			break;
		}

		rc = decode_get_pdr_req(msg, PLDM_GET_PDR_REQ_BYTES, &record_handle, &data_transfer_handle,
					&transfer_opflag, &request_cnt, &record_chg_num);

		if (rc != 0) {
			LOG_INF("Failed to decode get pdr request %d", rc);
			rc = encode_get_pdr_resp(instance, PLDM_ERROR, 0, 0,
						 PLDM_PLATFORM_TRANSFER_START_AND_END, 0, NULL, 0,
						 resp_msg);
			__ASSERT(rc == 0, "Failed to encode get pdr response");
			break;
		}

		/* No multipart support yet */
		if (transfer_opflag != PLDM_GET_FIRSTPART || data_transfer_handle != 0) {
			LOG_WRN("Received get pdr request with unsupported transfer operation flag %d or non-zero data transfer handle %d",
				transfer_opflag, data_transfer_handle);
			rc = encode_get_pdr_resp(instance, PLDM_ERROR, 0, 0,
						 PLDM_PLATFORM_TRANSFER_START_AND_END, 0, NULL, 0,
						 resp_msg);
			__ASSERT(rc == 0, "Failed to encode get pdr response");
			break;
		}

		/* Find the requested record */
		if (record_handle >= pdrs_len) {
			LOG_WRN("Received get pdr request with invalid record handle %d, max is %d",
				record_handle, pdrs_len - 1);
			rc = encode_get_pdr_resp(instance, PLDM_PLATFORM_INVALID_RECORD_HANDLE, 0, 0,
						 PLDM_PLATFORM_TRANSFER_START_AND_END, 0, NULL, 0,
						 resp_msg);
			__ASSERT(rc == 0, "Failed to encode get pdr response");
			break;
		}

		/* Does the record fit it the request_cnt? Remember, no multipart yet... */
		if ((pdrs[record_handle]->length + sizeof(struct pldm_pdr_hdr)) > request_cnt) {
			LOG_WRN("Received get pdr request with request count %d that is too small for the record length %d",
				request_cnt, pdrs[record_handle]->length + sizeof(struct pldm_pdr_hdr));
			rc = encode_get_pdr_resp(instance, PLDM_ERROR, 0, 0,
						 PLDM_PLATFORM_TRANSFER_START_AND_END, 0, NULL, 0,
						 resp_msg);
			__ASSERT(rc == 0, "Failed to encode get pdr response");
			break;
		}

		next_record_handle = record_handle + 1 < pdrs_len ? record_handle + 1 : 0;
		rc = encode_get_pdr_resp(instance, PLDM_SUCCESS, next_record_handle, 0,
					 PLDM_PLATFORM_TRANSFER_START_AND_END,
					 pdrs[record_handle]->length,
					 (const uint8_t *)pdrs[record_handle],
					 pldm_edac_crc8((uint8_t *)pdrs[record_handle],
							pdrs[record_handle]->length + sizeof(struct pldm_pdr_hdr)),
					 resp_msg);
		__ASSERT(rc == 0, "Failed to encode get pdr response");

		resp_msg_len += pdrs[record_handle]->length;

		break;
	}
	case PLDM_GET_SENSOR_READING: {
		uint16_t sensor_id;
		bool8_t rearm;
		uint8_t completion_code;
		uint8_t sensor_data_buffer[8]; /* Should be enough */
		uint8_t sensor_data_size;
		uint8_t sensor_operation_state;
		uint8_t sensor_event_message_enable;
		uint8_t present_state;
		uint8_t previous_state;
		uint8_t event_state;
		size_t payload_len;

		resp_msg_len = PLDM_MSG_SIZE(PLDM_GET_SENSOR_READING_MIN_RESP_BYTES) + 1;

		if (cbs->numeric_sensor_reading == NULL) {
			LOG_WRN("Received get version request but no callbacks registered, cannot reply");
			rc = encode_get_sensor_reading_resp(instance, PLDM_ERROR_UNSUPPORTED_PLDM_CMD,
							    0, 0, 0, 0, 0, 0, NULL, resp_msg,
							    PLDM_GET_SENSOR_READING_MIN_RESP_BYTES);
			__ASSERT(rc == 0, "Failed to encode get sensor reading response");
			break;
		}

		/* First decode request to get the sensor id and rearm flag */
		if (msg_len < PLDM_GET_SENSOR_READING_REQ_BYTES) {
			LOG_WRN("Received get sensor reading request with invalid length %d, expected at least %d",
				msg_len, PLDM_GET_SENSOR_READING_REQ_BYTES);
			rc = encode_get_sensor_reading_resp(instance, PLDM_ERROR_INVALID_LENGTH,
							    0, 0, 0, 0, 0, 0, NULL, resp_msg,
							    PLDM_GET_SENSOR_READING_MIN_RESP_BYTES);
			__ASSERT(rc == 0, "Failed to encode get sensor reading response");
			break;
		}

		rc = decode_get_sensor_reading_req(msg, msg_len, &sensor_id, &rearm);
		if (rc != 0) {
			LOG_INF("Failed to decode get sensor reading request %d", rc);
			rc = encode_get_sensor_reading_resp(instance, PLDM_ERROR,
							    0, 0, 0, 0, 0, 0, NULL, resp_msg,
							    PLDM_GET_SENSOR_READING_MIN_RESP_BYTES);
			__ASSERT(rc == 0, "Failed to encode get sensor reading response");
			break;
		}

		rc = cbs->numeric_sensor_reading(sensor_id, rearm, &completion_code, &sensor_data_size,
						 &sensor_operation_state, &sensor_event_message_enable,
						 &present_state, &previous_state, &event_state,
						 sensor_data_buffer);

		if (rc != 0) {
			LOG_INF("Failed to get sensor reading from callback %d", rc);
			rc = encode_get_sensor_reading_resp(instance, PLDM_ERROR,
							    0, 0, 0, 0, 0, 0, NULL, resp_msg,
							    PLDM_GET_SENSOR_READING_MIN_RESP_BYTES);
			__ASSERT(rc == 0, "Failed to encode get sensor reading response");
			break;
		}

		payload_len = PLDM_GET_SENSOR_READING_MIN_RESP_BYTES;
		switch (sensor_data_size) {
		case PLDM_SENSOR_DATA_SIZE_UINT8:
		case PLDM_SENSOR_DATA_SIZE_SINT8:
			resp_msg_len += sizeof(uint8_t);
			payload_len += sizeof(uint8_t);
			break;
		case PLDM_SENSOR_DATA_SIZE_UINT16:
		case PLDM_SENSOR_DATA_SIZE_SINT16:
			resp_msg_len += sizeof(uint16_t);
			payload_len += sizeof(uint16_t);
			break;
		case PLDM_SENSOR_DATA_SIZE_UINT32:
		case PLDM_SENSOR_DATA_SIZE_SINT32:
			resp_msg_len += sizeof(uint32_t);
			payload_len += sizeof(uint32_t);
			break;
		default:
			LOG_WRN("Invalid sensor data size %d returned from callback", sensor_data_size);
			rc = encode_get_sensor_reading_resp(instance, PLDM_ERROR,
							    0, 0, 0, 0, 0, 0, NULL, resp_msg,
							    PLDM_GET_SENSOR_READING_MIN_RESP_BYTES);
			break; /* Out of inner switch */
		}
		if (rc != 0) {
			break;
		}

		/* Need to take one from resp_msg_len/payload_len since there's one byte already
		 * accounted for
		 */
		resp_msg_len--;
		payload_len--;

		rc = encode_get_sensor_reading_resp(instance, completion_code, sensor_data_size, sensor_operation_state,
						    sensor_event_message_enable, present_state, previous_state,
						    event_state, sensor_data_buffer, resp_msg, payload_len);
		__ASSERT(rc == 0, "Failed to encode get sensor reading response");

		break;
	}
	default:
		LOG_INF("unhandled message command %d and type %d", hdr_info.command,
			hdr_info.msg_type);
		return -EINVAL;
	}

	inc_instance();
	LOG_HEXDUMP_DBG(resp_msg_buf, resp_msg_len, "response message being sent");
	LOG_DBG("With %u bytes", resp_msg_len);
	return mctp_message_tx(mctp_ctx, src_eid, false, 0, resp_msg_buf, resp_msg_len);
}
