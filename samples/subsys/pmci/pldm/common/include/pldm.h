#ifndef ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_PLDM_H
#define ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_PLDM_H

#include <libpldm/base.h>
#include <libpldm/platform.h>
#include <libmctp.h>

#define MCTP_MESSAGE_TYPE_MASK 0x7F
#define PLDM_MCTP_MESSAGE_TYPE 1

/* PLDM_FILE is the last one, but we need to account for PLDM_OEM and of course, the 0-indexing */
#define PLDM_TYPES_LEN (PLDM_FILE + 1 + 1)

struct pldm_type_info {
	ver32_t version;
	bitfield8_t commands[32];
};

struct pldm_tid_info {
	uint8_t tid;
	bitfield8_t types[8];
	struct pldm_type_info type_infos[PLDM_TYPES_LEN];
};
#define PLDM_TYPE_INFO_IDX(type) (type == PLDM_OEM ? PLDM_TYPES_LEN - 1 : type)

struct pldm_commands_cb {
	int (*numeric_sensor_reading)(uint16_t sensor_id, bool8_t rearm, uint8_t *comp_code,
				      uint8_t *sensor_data_size, uint8_t *sensor_operational_state,
				      uint8_t *sensor_event_message_enable, uint8_t *present_state,
				      uint8_t *previous_state, uint8_t *event_state,
				      const uint8_t *present_reading);
};

static inline bool is_bit_set(bitfield8_t *bitfield, uint32_t bit)
{
	int byte_idx = bit / 8;
	int bit_idx = bit % 8;

	return IS_BIT_SET(bitfield[byte_idx].byte, bit_idx);
}

void pldm_response_handler(struct pldm_msg *msg, size_t len);

int pldm_discovery(struct mctp *mctp_ctx, uint8_t eid, struct pldm_tid_info *tid_info);

int pldm_get_pdr(struct mctp *mctp_ctx, uint8_t eid, uint16_t record_handle, uint8_t *pdr_buf,
		 size_t *pdr_len);

int pldm_get_sensor_reading(struct mctp *mctp_ctx, uint8_t eid, uint16_t sensor_id,
			    void *reading_data, size_t *reading_len, uint8_t *present_state);

int pldm_request_handler(struct mctp *mctp_ctx, uint8_t eid, struct pldm_tid_info *tid_info,
			 struct pldm_pdr_hdr *pdrs[], size_t pdrs_len, struct pldm_commands_cb *cbs,
			 struct pldm_msg *msg, size_t msg_len);

void log_commands(enum pldm_supported_types type, bitfield8_t *commands);

void log_types(bitfield8_t *types);

#endif /* ZEPHYR_SAMPLES_SUBSYS_PMCI_DEMO_PLDM_H */
