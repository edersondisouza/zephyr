/*
 * Copyright (c) 2025 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <zephyr/types.h>
#include <zephyr/kernel.h>
#include <libmctp.h>
#include <zephyr/pmci/mctp/mctp_i2c_gpio_controller.h>
#include <zephyr/pmci/mctp/mctp_uart.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(controller_mctp_endpoint);

#define LOCAL_EID 20
#define SENSOR_EID 15
#define DISPLAY_EID 11

MCTP_I2C_GPIO_CONTROLLER_DT_DEFINE(mctp_i2c_ctrl, DT_NODELABEL(mctp_i2c));
MCTP_UART_DT_DEFINE(mctp_uart, DEVICE_DT_GET(DT_NODELABEL(arduino_serial)));

struct mctp *mctp_ctx;
struct mctp *mctp_ctx_uart;

struct temperature_data {
	double temperature;
	bool updated;
} __packed;

struct temperature_data last_temperature;

static void rx_message(uint8_t eid, bool tag_owner, uint8_t msg_tag, void *data, void *msg,
		       size_t len)
{
	if (eid == SENSOR_EID) {
		LOG_INF("Sensor EID message received: %.2f", *((double *)msg));
		last_temperature.temperature = *((double *)msg);
		last_temperature.updated = true;
	} else {
		LOG_INF("received message %s from endpoint %d to %d, msg_tag %d, len %zu", (char *)msg, eid,
			LOCAL_EID, msg_tag, len);
	}
}

int main(void)
{
	LOG_INF("Controller EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	mctp_set_alloc_ops(malloc, free, realloc);
	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_ctx_uart = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx_uart != NULL);
	mctp_register_bus(mctp_ctx, &mctp_i2c_ctrl.binding, LOCAL_EID);
	mctp_register_bus(mctp_ctx_uart, &mctp_uart.binding, LOCAL_EID);
	mctp_set_rx_all(mctp_ctx, rx_message, NULL);
	mctp_set_rx_all(mctp_ctx_uart, rx_message, NULL);
	mctp_uart_start_rx(&mctp_uart);

	while (true) {
		LOG_INF("Sending message to Display EID:");
		LOG_INF("\tTemperature: %.2f°C - Up-to-date: %d",
			last_temperature.temperature, last_temperature.updated);
		mctp_message_tx(mctp_ctx, DISPLAY_EID, false, 0, &last_temperature, sizeof(last_temperature));
		last_temperature.updated = false;

		k_sleep(K_SECONDS(2));
	}

	return 0;
}
