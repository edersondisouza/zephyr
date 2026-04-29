/*
 * Copyright (c) 2018 Jan Van Winkel <jan.van_winkel@dxplore.eu>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/display.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/led.h>
#include <lvgl.h>
#include <stdio.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <lvgl_input_device.h>

#include <math.h>
#include <libmctp.h>
#include <libmctp-cmds.h>
#include <control.h>
#include <zephyr/pmci/mctp/mctp_i2c_gpio_target.h>
#include <zephyr/pmci/mctp/mctp_uart.h>

#include <mctp.h>

#define LOG_LEVEL CONFIG_LOG_DEFAULT_LEVEL
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(app);

#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_i2c))
MCTP_I2C_GPIO_TARGET_DT_DEFINE(mctp_endpoint, DT_NODELABEL(mctp_i2c));
#define LOCAL_EID mctp_endpoint.endpoint_id
#elif DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
MCTP_UART_DT_DEFINE(mctp_endpoint, DEVICE_DT_GET(DT_NODELABEL(mctp_serial)));
#define LOCAL_EID 12
#endif

#define EC_EID 20

#define MCTP_MESSAGE_TYPE_MASK 0x7F

struct temperature_data {
	double temperature;
	bool updated;
} __packed;
struct temperature_data temperature;
bool use_farenheit;

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

static void rx_message_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	while (true) {
		struct message *rx_msg = k_fifo_get(&rx_fifo, K_NO_WAIT);
		if (!rx_msg) {
			break;
		}

		LOG_DBG("Processing MCTP control message from mctp endpoint %d, len %zu", rx_msg->src_eid, rx_msg->len);
		LOG_HEXDUMP_DBG(rx_msg->data, rx_msg->len, "MCTP control message");

		mctp_control_handler(rx_msg->binding->bus, rx_msg->src_eid, rx_msg->tag_owner,
				     rx_msg->msg_tag, rx_msg->data, rx_msg->len);

		free(rx_msg);
	}
}
K_WORK_DEFINE(rx_message_work, rx_message_handler);

static void rx_message(uint8_t eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{

	uint8_t *msg_buf = (uint8_t *)msg;

	if ((msg_buf[0] & MCTP_MESSAGE_TYPE_MASK) == MCTP_CTRL_HDR_MSG_TYPE) {
		struct message *rx_msg = malloc(sizeof(struct message) + len);

		if (!rx_msg) {
			LOG_ERR("Failed to allocate memory for incoming message");
			return;
		}
		rx_msg->len = len;
		rx_msg->src_eid = eid;
		rx_msg->tag_owner = tag_owner;
		rx_msg->msg_tag = msg_tag;
		rx_msg->binding = data;
		memcpy(rx_msg->data, msg_buf, len);
		k_fifo_put(&rx_fifo, rx_msg);
		k_work_submit(&rx_message_work);

		return;
	}

	if (eid == EC_EID) {
		temperature = *(struct temperature_data *)msg;
		LOG_INF("Controller EID message received: %.2f Up-to-date: %d", temperature.temperature,
			temperature.updated);
	}
}

#if DT_NODE_EXISTS(DT_NODELABEL(led))
static const struct device *lcd_bl = DEVICE_DT_GET(DT_PARENT(DT_NODELABEL(led)));
#endif

static void temperature_label_click_cb(lv_event_t *e)
{
	use_farenheit = !use_farenheit;

	LOG_INF("Temperature unit changed to %s", use_farenheit ? "Farenheit" : "Celsius");
}

int main(void)
{
	char temperature_str[12] = {0};
	const struct device *display_dev;
	lv_obj_t *temperature_label;
	int ret;
	lv_obj_t *arc;
	lv_style_t style_indic, style_text;
	struct mctp *mctp_ctx;

	LOG_INF("Display EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	display_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_display));
	if (!device_is_ready(display_dev)) {
		LOG_ERR("Device not ready, aborting test");
		return 0;
	}

#if DT_NODE_EXISTS(DT_NODELABEL(led))
	led_on(lcd_bl, 0);
#endif

	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_register_bus(mctp_ctx, &mctp_endpoint.binding, LOCAL_EID);
	/* For some reason, libmctp doesn't add the base type by default */
	mctp_control_add_type(mctp_ctx, MCTP_MSG_TYPE_NUMBER_MCTP_BASE);
	mctp_set_rx_all(mctp_ctx, rx_message, &mctp_endpoint.binding);
#if DT_NODE_HAS_STATUS_OKAY(DT_NODELABEL(mctp_serial))
	mctp_uart_start_rx(&mctp_endpoint);
#endif

	lv_style_init(&style_indic);

	arc = lv_arc_create(lv_screen_active());
	lv_obj_center(arc);
	lv_obj_add_style(arc, &style_indic, LV_PART_INDICATOR);
	lv_obj_set_size(arc, 220, 220);
	lv_obj_remove_style(arc, NULL, LV_PART_KNOB);
	lv_obj_clear_flag(arc, LV_OBJ_FLAG_CLICKABLE);

	lv_style_init(&style_text);
	lv_style_set_text_font(&style_text, &lv_font_montserrat_48);

	temperature_label = lv_label_create(lv_screen_active());
	lv_obj_add_style(temperature_label, &style_text, 0);
	lv_label_set_text(temperature_label, "--");
	lv_obj_center(temperature_label);
	lv_obj_add_flag(temperature_label, LV_OBJ_FLAG_CLICKABLE);
	lv_obj_add_event_cb(temperature_label, temperature_label_click_cb, LV_EVENT_CLICKED, NULL);

	lv_timer_handler();
	ret = display_blanking_off(display_dev);
	if (ret < 0 && ret != -ENOSYS) {
		LOG_ERR("Failed to turn blanking off (error %d)", ret);
		return 0;
	}

	while (1) {
		double temp_clamped = temperature.temperature;

		if (isnan(temp_clamped) || temp_clamped < 0.0) {
			temp_clamped = 0.0;
		} else if (temp_clamped > 100.0) {
			temp_clamped = 100.0;
		}
		if (use_farenheit) {
			double temp_f = (temperature.temperature * 9.0 / 5.0) + 32.0;
			sprintf(temperature_str, "%.2f°F", temp_f);
		} else {
			sprintf(temperature_str, "%.2f°C", temperature.temperature);
		}
		lv_label_set_text(temperature_label, temperature_str);
		lv_arc_set_value(arc, (int)temp_clamped);

		if (temperature.updated) {
			lv_style_set_text_color(&style_text, lv_color_black());
		} else {
			lv_style_set_text_color(&style_text, lv_color_hex(0x888888));
		}

		/* Varies color from blue to red proportionaly to the 0-100 count */
		lv_style_set_arc_color(&style_indic,
			lv_color_mix(
				lv_palette_main(LV_PALETTE_RED),
				lv_palette_main(LV_PALETTE_BLUE),
				(temp_clamped / 100) * (255/100)));

		lv_timer_handler();
		/* Sleep just a little to keep responsive */
		k_sleep(K_MSEC(10));
	}
}
