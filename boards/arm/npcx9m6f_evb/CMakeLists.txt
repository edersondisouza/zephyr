#
# Copyright (c) 2024 Intel Corporation.
#
# SPDX-License-Identifier: Apache-2.0
#

# Allow users to define SPI config layout'
set_property(GLOBAL APPEND PROPERTY extra_post_build_commands
    COMMAND cp ${PROJECT_BINARY_DIR}/zephyr.npcx.bin ${PROJECT_BINARY_DIR}/spi_image.bin && truncate -s 256K ${PROJECT_BINARY_DIR}/spi_image.bin
  )
