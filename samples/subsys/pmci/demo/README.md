== MCTP/PLDM demo ==

This demo shows a three board arrangement, where the boards share information
using MCTP and PLDM. One board acts as a sensor board, and replies to PLDM requests
so that one can read the PDR information from its sensor. The sensor board is connected
to a Grove kit temperature sensor, and it replies to PLDM sensor read requests with the
temperature readings. The controller board is the one that queries the sensor board
and subsequently send PLDM read requests to it. The controller board then forwards the
results to a display board using MCTP, and the display board shows the temperature on an LCD.
Note that the controller to display board communication is MCTP only, and does not use PLDM,
but instead a custom data format.

=== Setup ===

This demo was tested using two Nuvoton NPCX4 (Ramon) and one NXP MCXN947. Check the
overlays on each project unders this folder (sensor, controller and display) for
information on how to wire then. Besides connecting a Grove kit temperature sensor
to the sensor board and an LCD to the display board, you need to connect the I2C between
the controller and display board, as well as I3C between the sensor and controller boards.
Finally, connect the ground between all three boards.

=== Optional fourth board ===

The controller also searches for a sensor over I2C+GPIO when it fails to find the I3C sensor.
If you have a fourth board, you can set it up as an I2C+GPIO sensor board, and connect it to
the controller. The controller will then read the temperature from this board instead of the
I3C sensor. A hint here is to use the endpoint from the PLDM sample as a starting point for
the application of this fourth board, and modify it to use I2C+GPIO.
