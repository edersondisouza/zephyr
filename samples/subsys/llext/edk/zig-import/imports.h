/*
 * The Zephyr surface the bindings are generated from.
 *
 * An application adds its own header on top of this one -- see
 * app/zig/imports.h -- because its __syscall declarations are its own and
 * differ from application to application.
 */
#include <autoconf.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/llext/symbol.h>
