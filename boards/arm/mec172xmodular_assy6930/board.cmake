# SPDX-License-Identifier: Apache-2.0

set(SPI_IMAGE_NAME spi_image.bin)

board_set_flasher_ifnset(dediprog)

# --vcc=0 - use 3.5V to flash
board_finalize_runner_args(dediprog
  "--spi-image=${PROJECT_BINARY_DIR}/${SPI_IMAGE_NAME}"
  "--vcc=0"
)

set(SUPPORTED_EMU_PLATFORMS renode)
set(RENODE_SCRIPT ${CMAKE_CURRENT_LIST_DIR}/support/mec17xmodular_assy6930.resc)
set(RENODE_UART sysbus.uart1)
