#ifndef ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_MCTP_H
#define ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_MCTP_H

#include <libmctp.h>
#include <libmctp-cmds.h>

#define MCTP_MSG_TYPE_NUMBER_MCTP_BASE 0xFF
#define MCTP_MSG_TYPE_NUMBER_MCTP_CTRL 0x00
#define MCTP_MSG_TYPE_NUMBER_PLDM_MCTP 0x01

#define MCTP_MESSAGE_TYPE_MASK 0x7F

struct mctp_msg_type {
	uint8_t type;
	uint32_t *versions;
	size_t versions_len;
};

struct mctp_endpoint_info {
	uint8_t eid;
	uint8_t type;
	struct mctp_msg_type *msg_types;
	size_t msg_types_len;
};

int mctp_static_discovery(struct mctp *ctx, uint8_t eid, struct mctp_endpoint_info **endpoint_info);

void mctp_response_handler(uint8_t *msg_buf, size_t len);

void mctp_endpoint_info_log(struct mctp_endpoint_info *info);

void mctp_endpoint_info_free(struct mctp_endpoint_info *info);

void mctp_control_request_handler(struct mctp_binding *binding, mctp_eid_t src_eid, bool tag_owner,
				  uint8_t msg_tag, void *data, size_t len,
				  bool (*msg_type_versions)(uint8_t msg_type, uint32_t **versions, size_t *versions_len));

#endif /* ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_MCTP_H */
