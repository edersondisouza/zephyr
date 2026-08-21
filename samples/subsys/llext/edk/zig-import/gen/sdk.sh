#!/bin/bash
# Locate a Zephyr SDK binutil.
#
# The SDK installs these as arm-zephyr-eabi-*, not the arm-none-eabi-* names
# the sample's build scripts used to assume -- and typically not on PATH.
#
# Sourced, not executed.

sdk_tool() {
    local base="$1" cand
    for cand in "arm-zephyr-eabi-$base" \
                "${ZEPHYR_SDK_INSTALL_DIR:-}/arm-zephyr-eabi/bin/arm-zephyr-eabi-$base" \
                "$HOME"/zephyr-sdk-*/arm-zephyr-eabi/bin/"arm-zephyr-eabi-$base" \
                "$HOME"/zephyr-sdk-*/gnu/arm-zephyr-eabi/bin/"arm-zephyr-eabi-$base"; do
        if command -v "$cand" >/dev/null 2>&1; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}
