#include <zephyr/kernel.h>
#include <zephyr/sys/math_extras.h>

#include <stdlib.h>

#include <libmctp-cmds.h>
#include <control.h>

#include "mctp.h"

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(mctp, CONFIG_MCTP_LOG_LEVEL);

/* libmctp `mctp_message_tx_request` takes ownership of the buffer, so
 * we need to allocate it from the same heap libmctp uses, hence using
 * `mctp_heap_alloc` here
 */
extern void *mctp_heap_alloc(size_t bytes);

static struct mctp_endpoint_info *endpoint;
static int current_type_idx = 0;

K_SEM_DEFINE(mctp_discovery_rx, 0, 1);

void mctp_endpoint_info_free(struct mctp_endpoint_info *info)
{
	if (!info) {
		return;
	}

	if (info->msg_types) {
		for (size_t i = 0; i < info->msg_types_len; i++) {
			free(info->msg_types[i].versions);
		}
		free(info->msg_types);
		info->msg_types = NULL;
		info->msg_types_len = 0;
	}
	info->eid = 0;
	info->type = 0;
	free(info);
}

static uint8_t mctp_bcd_to_bin(uint8_t bcd)
{
	if (bcd & 0xF0) {
		/* If the upper nibble is set, ignore it and treat as a single digit */
		return bcd & 0x0F;
	}
	return (bcd & 0x0F) + ((bcd >> 4) * 10);
}

static void mctp_bcd_update_to_str(char *str, size_t len, uint8_t bcd)
{
	if (bcd == 0xFF) {
		str[0] = '\0';
		return;
	}

	snprintf(str, len, ".%d", mctp_bcd_to_bin(bcd));
}

void mctp_endpoint_info_log(struct mctp_endpoint_info *info)
{
	LOG_INF("Endpoint ID: %d Type: '%s' EID Type: '%s'", info->eid,
			(info->type & 0x10) ? "Bus Owner/Bridge" : "Simple",
			(info->type & 0x03) == 0 ? "Dynamic" :
			 ((info->type & 0x03) == 1 ? "Static" :
			  ((info->type & 0x03) == 2 ? "Static Same" : "Static Different")));

	LOG_INF("Supported Message Types:");
	for (size_t i = 0; i < info->msg_types_len; i++) {
		char *msg_type_str;

		switch (info->msg_types[i].type) {
		case MCTP_MSG_TYPE_NUMBER_MCTP_BASE:
			msg_type_str = "MCTP Base";
			break;
		case MCTP_MSG_TYPE_NUMBER_MCTP_CTRL:
			msg_type_str = "MCTP Control";
			break;
		case MCTP_MSG_TYPE_NUMBER_PLDM_MCTP:
			msg_type_str = "PLDM";
			break;
		default:
			msg_type_str = "Unknown";
		}

		LOG_INF("\tMessage Type: %d (%s)", info->msg_types[i].type, msg_type_str);
		for (size_t j = 0; j < info->msg_types[i].versions_len; j++) {
			uint32_t version = info->msg_types[i].versions[j];
			char update_str[16] = {0};

			mctp_bcd_update_to_str(update_str, sizeof(update_str), (version >> 16) & 0xFF);
			LOG_INF("\t\tVersion %zu: %d.%d%s%c", j,
				mctp_bcd_to_bin(version & 0xFF),
				mctp_bcd_to_bin((version >> 8) & 0xFF),
				update_str,
				((version >> 24) & 0xFF) == 0 ? '\0' : (version >> 24) & 0xFF);
		}
	}
}

void mctp_response_handler(uint8_t *msg_buf, size_t len)
{
	if ((msg_buf[0] & MCTP_MESSAGE_TYPE_MASK) != MCTP_CTRL_HDR_MSG_TYPE) {
		LOG_WRN("Received non-control message, ignoring");
		return;
	}

	LOG_HEXDUMP_DBG(msg_buf, len, "Received MCTP Control Message");

	struct mctp_ctrl_msg_hdr *hdr = (struct mctp_ctrl_msg_hdr *)msg_buf;
	LOG_DBG("MCTP Control Message - Command Code: %d, Instance ID: %d, Request: %d",
		hdr->command_code, hdr->rq_dgram_inst & MCTP_CTRL_HDR_INSTANCE_ID_MASK,
		(hdr->rq_dgram_inst & MCTP_CTRL_HDR_FLAG_REQUEST) != 0);

	switch (hdr->command_code) {
	case MCTP_CTRL_CMD_GET_ENDPOINT_ID: {
			struct mctp_ctrl_cmd_get_endpoint_id_resp *resp = (struct mctp_ctrl_cmd_get_endpoint_id_resp *)msg_buf;
			LOG_DBG("MCTP Control Response - Endpoint ID: %d, Result: %d, Type: %u",
				resp->endpoint_id, resp->completion_code, resp->endpoint_type);
			endpoint->eid = resp->endpoint_id;
			endpoint->type = resp->endpoint_type;
		}
		break;

	case MCTP_CTRL_CMD_GET_VERSION_SUPPORT: {
			struct mctp_ctrl_cmd_get_version_resp *resp = (struct mctp_ctrl_cmd_get_version_resp *)msg_buf;
			LOG_DBG("MCTP Control Response - Version Support, Result: %d, Version Count: %d",
				resp->completion_code, resp->version_count);
			endpoint->msg_types[current_type_idx].versions_len = resp->version_count;
			endpoint->msg_types[current_type_idx].versions = calloc(resp->version_count, sizeof(uint32_t));
			for (int i = 0; i < resp->version_count; i++) {
				endpoint->msg_types[current_type_idx].versions[i] = resp->versions[i];
			}
			current_type_idx++;
		}
		break;

	case MCTP_CTRL_CMD_GET_MESSAGE_TYPE_SUPPORT: {
			struct mctp_ctrl_cmd_get_types_resp *resp = (struct mctp_ctrl_cmd_get_types_resp *)msg_buf;
			LOG_DBG("MCTP Control Response - Message Type Support, Result: %d, Type Count: %d",
				resp->completion_code, resp->type_count);
			endpoint->msg_types_len = resp->type_count;
			endpoint->msg_types = calloc(resp->type_count, sizeof(struct mctp_msg_type));
			current_type_idx = 0;
			if (!endpoint->msg_types) {
				LOG_ERR("Failed to allocate memory for message types");
				break;
			}
			for (int i = 0; i < resp->type_count; i++) {
				endpoint->msg_types[i].type = resp->types[i];
			}
		}
		break;
	}

	k_sem_give(&mctp_discovery_rx);
}

int mctp_static_discovery(struct mctp *ctx, uint8_t eid, struct mctp_endpoint_info **endpoint_info)
{
	int i, rc;
	uint32_t instance_id = 0;
	uint8_t tag;
	struct mctp_ctrl_msg_hdr *get_endpoint_id_req, *get_supported_types_req;
	struct mctp_ctrl_cmd_get_version_req *get_version_req;

	*endpoint_info = malloc(sizeof(struct mctp_endpoint_info));
	if (!*endpoint_info) {
		LOG_ERR("Failed to allocate memory for endpoint info");
		return -ENOMEM;
	}

	endpoint = *endpoint_info;

	get_endpoint_id_req = mctp_heap_alloc(sizeof(struct mctp_ctrl_msg_hdr));
	if (!get_endpoint_id_req) {
		LOG_ERR("Failed to allocate memory for MCTP control message");
		return -ENOMEM;
	}

	*get_endpoint_id_req = (struct mctp_ctrl_msg_hdr) {
		.ic_msg_type = MCTP_CTRL_HDR_MSG_TYPE,
		.rq_dgram_inst = MCTP_CTRL_HDR_FLAG_REQUEST |
			(instance_id & MCTP_CTRL_HDR_INSTANCE_ID_MASK),
		.command_code = MCTP_CTRL_CMD_GET_ENDPOINT_ID,
	};

	LOG_DBG("Sending Get Endpoint ID command to EID %d", eid);

	rc = mctp_message_tx_request(ctx, eid, get_endpoint_id_req,
				     sizeof(*get_endpoint_id_req), &tag);
	LOG_DBG("Got tag %d for Get Endpoint ID request", tag);
	k_sem_take(&mctp_discovery_rx, K_FOREVER);

	if (endpoint->eid != eid) {
		LOG_ERR("Endpoint ID mismatch! Expected %d, got %d", eid, endpoint->eid);
		return -ENOENT;
	}

	LOG_DBG("Getting supported MCTP message types");
	get_supported_types_req = mctp_heap_alloc(sizeof(struct mctp_ctrl_msg_hdr));
	if (!get_supported_types_req) {
		LOG_ERR("Failed to allocate memory for MCTP control message");
		return -ENOMEM;
	}

	instance_id++;
	*get_supported_types_req = (struct mctp_ctrl_msg_hdr) {
		.ic_msg_type = MCTP_CTRL_HDR_MSG_TYPE,
		.rq_dgram_inst = MCTP_CTRL_HDR_FLAG_REQUEST |
			(instance_id & MCTP_CTRL_HDR_INSTANCE_ID_MASK),
		.command_code = MCTP_CTRL_CMD_GET_MESSAGE_TYPE_SUPPORT,
	};
	rc = mctp_message_tx_request(ctx, eid, get_supported_types_req,
				     sizeof(*get_supported_types_req), &tag);
	LOG_DBG("Got tag %d for Get Message Type Support request", tag);
	k_sem_take(&mctp_discovery_rx, K_FOREVER);

	for (i = 0; i < endpoint->msg_types_len; i++) {
		LOG_DBG("Getting versions supported for message type %d", endpoint->msg_types[i].type);

		instance_id++;
		get_version_req = mctp_heap_alloc(sizeof(struct mctp_ctrl_cmd_get_version_req));
		if (!get_version_req) {
			LOG_ERR("Failed to allocate memory for MCTP control message");
			return -ENOMEM;
		}

		*get_version_req = (struct mctp_ctrl_cmd_get_version_req) {
			.hdr.ic_msg_type = MCTP_CTRL_HDR_MSG_TYPE,
			.hdr.rq_dgram_inst = MCTP_CTRL_HDR_FLAG_REQUEST |
				(instance_id & MCTP_CTRL_HDR_INSTANCE_ID_MASK),
			.hdr.command_code = MCTP_CTRL_CMD_GET_VERSION_SUPPORT,
			.msg_type = endpoint->msg_types[i].type,
		};
		rc = mctp_message_tx_request(ctx, eid, get_version_req,
					     sizeof(*get_version_req), &tag);
		LOG_DBG("Got tag %d for Get Version Support request for message type %d", tag, endpoint->msg_types[i].type);
		k_sem_take(&mctp_discovery_rx, K_FOREVER);
	}

	LOG_DBG("Done with MCTP ensure for EID %d", eid);

	return 0;
}

void mctp_control_request_handler(struct mctp_binding *binding, mctp_eid_t src_eid, bool tag_owner,
				  uint8_t msg_tag, void *data, size_t len,
				  bool (*msg_type_versions)(uint8_t msg_type, uint32_t **versions, size_t *versions_len))
{
	/* Is this a get versions request? */
	struct mctp_ctrl_msg_hdr *hdr = (struct mctp_ctrl_msg_hdr *)data;

	if ((hdr->ic_msg_type & MCTP_MESSAGE_TYPE_MASK) != MCTP_CTRL_HDR_MSG_TYPE) {
		LOG_WRN("Received non-control message, ignoring");
		return;
	}

	if ((hdr->rq_dgram_inst & MCTP_CTRL_HDR_FLAG_REQUEST) == 0 || !tag_owner) {
		LOG_WRN("Received control message that is not a request, ignoring");
		return;
	}

	if (hdr->command_code == MCTP_CTRL_CMD_GET_VERSION_SUPPORT) {
		const struct mctp_ctrl_cmd_get_version_req *req = data;

		switch (req->msg_type) {
		case MCTP_MSG_TYPE_NUMBER_MCTP_BASE:
		case MCTP_MSG_TYPE_NUMBER_MCTP_CTRL:
			break; /* These are handled by libmctp*/

		default:
			if (msg_type_versions) {
				uint32_t *versions;
				size_t versions_len, resp_size;

				if (!msg_type_versions(req->msg_type, &versions, &versions_len)) {
					LOG_WRN("Message type %d not supported, cannot respond to version request", req->msg_type);
					break; /* Let libmctp reply with an error */
				}

				if (size_mul_overflow(versions_len, sizeof(uint32_t), &resp_size)) {
					LOG_ERR("Version count too large, cannot respond");
					return;
				}

				if (size_add_overflow(sizeof(struct mctp_ctrl_cmd_get_version_resp), resp_size, &resp_size)) {
					LOG_ERR("Response size overflow, cannot respond");
					return;
				}

				struct mctp_ctrl_cmd_get_version_resp *resp = mctp_heap_alloc(resp_size);
				if (!resp) {
					LOG_ERR("Failed to allocate memory for version response");
					return;
				}

				*resp = (struct mctp_ctrl_cmd_get_version_resp) {
					.hdr.ic_msg_type = MCTP_CTRL_HDR_MSG_TYPE,
					.hdr.rq_dgram_inst = (hdr->rq_dgram_inst & MCTP_CTRL_HDR_INSTANCE_ID_MASK),
					.hdr.command_code = hdr->command_code,
					.completion_code = MCTP_CTRL_CC_SUCCESS,
					.version_count = versions_len,
				};

				memcpy(resp->versions, versions, versions_len * sizeof(uint32_t));

				int rc = mctp_message_tx_alloced(binding->mctp, src_eid, false, msg_tag,
								 resp, resp_size);
				if (rc < 0) {
					LOG_ERR("Failed to send version support response: %d", rc);
				}
				return;
			}
			break;
		}
	}

	mctp_control_handler(binding->bus, src_eid, tag_owner, msg_tag, data, len);
}
