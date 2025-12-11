== MCTP demo ==

This demo shows a three board arrangement, where the boards share information
using MCTP. One board acts as a sensor board, periodically sending
temperature readings to a controller board. The controller board then
forwards these readings to a display board, which shows the temperature on an LCD.

=== Setup ===

This demo was tested using two Nuvoton NPCX4 (Ramon) and one NXP MCXN947. Check the
overlays on each project unders this folder (sensor, controller and display) for
information on how to wire then. Besides connecting a Grove kit temperature sensor
to the sensor board and an LCD to the display board, you need to connect the I2C between
the controller and display board, as well as UART between the sensor and controller boards
(remember to connext from one RX to TX on the other). Finally, connect the ground
between all three boards.
