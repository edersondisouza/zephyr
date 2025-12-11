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
#include <zephyr/pmci/mctp/mctp_uart.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(sensor_mctp_endpoint);

#define SLEEP_TIME	K_MSEC(1000)

MCTP_UART_DT_DEFINE(mctp_endpoint, DEVICE_DT_GET(DT_NODELABEL(arduino_serial)));
#define REMOTE_EID 20
#define LOCAL_EID 15

int main(void)
{
	const struct device *const dev = DEVICE_DT_GET_ONE(seeed_grove_temperature);
	struct sensor_value temp;
	double temperature_value;
	int read;
	struct mctp *mctp_ctx;

	if (!device_is_ready(dev)) {
		LOG_WRN("sensor: device not ready.\n");
		return 0;
	}

	LOG_INF("Sensor EID:%d on %s\n", LOCAL_EID, CONFIG_BOARD_TARGET);

	mctp_set_alloc_ops(malloc, free, realloc);
	mctp_ctx = mctp_init();
	__ASSERT_NO_MSG(mctp_ctx != NULL);
	mctp_register_bus(mctp_ctx, &mctp_endpoint.binding, LOCAL_EID);
	mctp_uart_start_rx(&mctp_endpoint);

	while (1) {
		int rc;

		read = sensor_sample_fetch(dev);
		if (read) {
			printk("sample fetch error %d\n", read);
			k_sleep(SLEEP_TIME);
			continue;
		}
		sensor_channel_get(dev, SENSOR_CHAN_AMBIENT_TEMP, &temp);
		temperature_value = sensor_value_to_double(&temp);
		LOG_INF("Read temperature: %.2f °C", temperature_value);

		LOG_INF("Sending it to Controller EID");
		rc = mctp_message_tx(mctp_ctx, REMOTE_EID, false,
				0, &temperature_value, sizeof(temperature_value));
		if (rc != 0) {
			printk("Failed to send message, errno %d\n", rc);
		}

		k_sleep(SLEEP_TIME);
	}
}
