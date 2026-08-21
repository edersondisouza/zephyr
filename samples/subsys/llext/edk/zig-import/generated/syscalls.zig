//! TIER 0 -- RAW SYSCALLS. GENERATED FILE, DO NOT EDIT.
//!
//! Regenerate with `gen/regen.sh` whenever the EDK's syscalls change.
//! One faithful wrapper per syscall the extension API can reach: C ABI
//! signatures lifted from cimport.zig, C error codes, no ergonomics.
//!
//! Extensions should not import this directly -- use the curated `zephyr`
//! API. It is reachable as `zephyr.uncurated` for syscalls nobody has
//! curated yet, and `gen/check.sh` reports every such use as curation work
//! still to do.
//!
//! Provenance: frdm_mcxn947_mcxn947_cpu0, 120 syscalls, from include/generated/zephyr/syscalls/*.h

const c = @import("cimport");
const p = @import("../gen/prelude.zig");

/// device.h :: K_SYSCALL_DEVICE_DEINIT, arity 1
pub fn device_deinit(arg_dev: [*c]const c.struct_device) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_dev), c.K_SYSCALL_DEVICE_DEINIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_device_deinit(arg_dev);
}

/// device.h :: K_SYSCALL_DEVICE_GET_BINDING, arity 1
pub fn device_get_binding(arg_name: [*c]const u8) [*c]const c.struct_device {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from([*c]const c.struct_device, p.arch_syscall_invoke1(p.cast(arg_name), c.K_SYSCALL_DEVICE_GET_BINDING));
        }
    }
    p.compiler_barrier();
    return c.z_impl_device_get_binding(arg_name);
}

/// device.h :: K_SYSCALL_DEVICE_GET_BY_DT_NODELABEL, arity 1
pub fn device_get_by_dt_nodelabel(arg_nodelabel: [*c]const u8) [*c]const c.struct_device {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from([*c]const c.struct_device, p.arch_syscall_invoke1(p.cast(arg_nodelabel), c.K_SYSCALL_DEVICE_GET_BY_DT_NODELABEL));
        }
    }
    p.compiler_barrier();
    return c.z_impl_device_get_by_dt_nodelabel(arg_nodelabel);
}

/// device.h :: K_SYSCALL_DEVICE_INIT, arity 1
pub fn device_init(arg_dev: [*c]const c.struct_device) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_dev), c.K_SYSCALL_DEVICE_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_device_init(arg_dev);
}

/// device.h :: K_SYSCALL_DEVICE_IS_READY, arity 1
pub fn device_is_ready(arg_dev: [*c]const c.struct_device) bool {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(bool, p.arch_syscall_invoke1(p.cast(arg_dev), c.K_SYSCALL_DEVICE_IS_READY));
        }
    }
    p.compiler_barrier();
    return c.z_impl_device_is_ready(arg_dev);
}

/// gpio.h :: K_SYSCALL_GPIO_GET_PENDING_INT, arity 1
pub fn gpio_get_pending_int(arg_dev: [*c]const c.struct_device) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_dev), c.K_SYSCALL_GPIO_GET_PENDING_INT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_get_pending_int(arg_dev);
}

/// gpio.h :: K_SYSCALL_GPIO_PIN_CONFIGURE, arity 3
pub fn gpio_pin_configure(arg_port: [*c]const c.struct_device, arg_pin: c.gpio_pin_t, arg_flags: c.gpio_flags_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_port), p.cast(arg_pin), p.cast(arg_flags), c.K_SYSCALL_GPIO_PIN_CONFIGURE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_pin_configure(arg_port, arg_pin, arg_flags);
}

/// gpio.h :: K_SYSCALL_GPIO_PIN_GET_CONFIG, arity 3
pub fn gpio_pin_get_config(arg_port: [*c]const c.struct_device, arg_pin: c.gpio_pin_t, arg_flags: [*c]c.gpio_flags_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_port), p.cast(arg_pin), p.cast(arg_flags), c.K_SYSCALL_GPIO_PIN_GET_CONFIG));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_pin_get_config(arg_port, arg_pin, arg_flags);
}

/// gpio.h :: K_SYSCALL_GPIO_PIN_INTERRUPT_CONFIGURE, arity 3
pub fn gpio_pin_interrupt_configure(arg_port: [*c]const c.struct_device, arg_pin: c.gpio_pin_t, arg_flags: c.gpio_flags_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_port), p.cast(arg_pin), p.cast(arg_flags), c.K_SYSCALL_GPIO_PIN_INTERRUPT_CONFIGURE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_pin_interrupt_configure(arg_port, arg_pin, arg_flags);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_CLEAR_BITS_RAW, arity 2
pub fn gpio_port_clear_bits_raw(arg_port: [*c]const c.struct_device, arg_pins: c.gpio_port_pins_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_port), p.cast(arg_pins), c.K_SYSCALL_GPIO_PORT_CLEAR_BITS_RAW));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_clear_bits_raw(arg_port, arg_pins);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_GET_DIRECTION, arity 4
pub fn gpio_port_get_direction(arg_port: [*c]const c.struct_device, arg_map: c.gpio_port_pins_t, arg_inputs: [*c]c.gpio_port_pins_t, arg_outputs: [*c]c.gpio_port_pins_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_port), p.cast(arg_map), p.cast(arg_inputs), p.cast(arg_outputs), c.K_SYSCALL_GPIO_PORT_GET_DIRECTION));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_get_direction(arg_port, arg_map, arg_inputs, arg_outputs);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_GET_RAW, arity 2
pub fn gpio_port_get_raw(arg_port: [*c]const c.struct_device, arg_value: [*c]c.gpio_port_value_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_port), p.cast(arg_value), c.K_SYSCALL_GPIO_PORT_GET_RAW));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_get_raw(arg_port, arg_value);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_SET_BITS_RAW, arity 2
pub fn gpio_port_set_bits_raw(arg_port: [*c]const c.struct_device, arg_pins: c.gpio_port_pins_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_port), p.cast(arg_pins), c.K_SYSCALL_GPIO_PORT_SET_BITS_RAW));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_set_bits_raw(arg_port, arg_pins);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_SET_MASKED_RAW, arity 3
pub fn gpio_port_set_masked_raw(arg_port: [*c]const c.struct_device, arg_mask: c.gpio_port_pins_t, arg_value: c.gpio_port_value_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_port), p.cast(arg_mask), p.cast(arg_value), c.K_SYSCALL_GPIO_PORT_SET_MASKED_RAW));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_set_masked_raw(arg_port, arg_mask, arg_value);
}

/// gpio.h :: K_SYSCALL_GPIO_PORT_TOGGLE_BITS, arity 2
pub fn gpio_port_toggle_bits(arg_port: [*c]const c.struct_device, arg_pins: c.gpio_port_pins_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_port), p.cast(arg_pins), c.K_SYSCALL_GPIO_PORT_TOGGLE_BITS));
        }
    }
    p.compiler_barrier();
    return c.z_impl_gpio_port_toggle_bits(arg_port, arg_pins);
}

/// kernel.h :: K_SYSCALL_K_BUSY_WAIT, arity 1
pub fn k_busy_wait(arg_usec_to_wait: u32) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_usec_to_wait), c.K_SYSCALL_K_BUSY_WAIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_busy_wait(arg_usec_to_wait);
}

/// kernel.h :: K_SYSCALL_K_CONDVAR_BROADCAST, arity 1
pub fn k_condvar_broadcast(arg_condvar: [*c]c.struct_k_condvar) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_condvar), c.K_SYSCALL_K_CONDVAR_BROADCAST));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_condvar_broadcast(arg_condvar);
}

/// kernel.h :: K_SYSCALL_K_CONDVAR_INIT, arity 1
pub fn k_condvar_init(arg_condvar: [*c]c.struct_k_condvar) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_condvar), c.K_SYSCALL_K_CONDVAR_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_condvar_init(arg_condvar);
}

/// kernel.h :: K_SYSCALL_K_CONDVAR_SIGNAL, arity 1
pub fn k_condvar_signal(arg_condvar: [*c]c.struct_k_condvar) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_condvar), c.K_SYSCALL_K_CONDVAR_SIGNAL));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_condvar_signal(arg_condvar);
}

/// kernel.h :: K_SYSCALL_K_CONDVAR_WAIT, arity 4
pub fn k_condvar_wait(arg_condvar: [*c]c.struct_k_condvar, arg_mutex: [*c]c.struct_k_mutex, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_condvar), p.cast(arg_mutex), _lo2, _hi2, c.K_SYSCALL_K_CONDVAR_WAIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_condvar_wait(arg_condvar, arg_mutex, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_EVENT_CLEAR, arity 2
pub fn k_event_clear(arg_event: [*c]c.struct_k_event, arg_events: u32) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke2(p.cast(arg_event), p.cast(arg_events), c.K_SYSCALL_K_EVENT_CLEAR));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_clear(arg_event, arg_events);
}

/// kernel.h :: K_SYSCALL_K_EVENT_INIT, arity 1
pub fn k_event_init(arg_event: [*c]c.struct_k_event) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_event), c.K_SYSCALL_K_EVENT_INIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_event_init(arg_event);
}

/// kernel.h :: K_SYSCALL_K_EVENT_POST, arity 2
pub fn k_event_post(arg_event: [*c]c.struct_k_event, arg_events: u32) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke2(p.cast(arg_event), p.cast(arg_events), c.K_SYSCALL_K_EVENT_POST));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_post(arg_event, arg_events);
}

/// kernel.h :: K_SYSCALL_K_EVENT_SET, arity 2
pub fn k_event_set(arg_event: [*c]c.struct_k_event, arg_events: u32) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke2(p.cast(arg_event), p.cast(arg_events), c.K_SYSCALL_K_EVENT_SET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_set(arg_event, arg_events);
}

/// kernel.h :: K_SYSCALL_K_EVENT_SET_MASKED, arity 3
pub fn k_event_set_masked(arg_event: [*c]c.struct_k_event, arg_events: u32, arg_events_mask: u32) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke3(p.cast(arg_event), p.cast(arg_events), p.cast(arg_events_mask), c.K_SYSCALL_K_EVENT_SET_MASKED));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_set_masked(arg_event, arg_events, arg_events_mask);
}

/// kernel.h :: K_SYSCALL_K_EVENT_WAIT, arity 5
pub fn k_event_wait(arg_event: [*c]c.struct_k_event, arg_events: u32, arg_reset: bool, arg_timeout: c.k_timeout_t) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(u32, p.arch_syscall_invoke5(p.cast(arg_event), p.cast(arg_events), p.cast(arg_reset), _lo3, _hi3, c.K_SYSCALL_K_EVENT_WAIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_wait(arg_event, arg_events, arg_reset, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_EVENT_WAIT_ALL, arity 5
pub fn k_event_wait_all(arg_event: [*c]c.struct_k_event, arg_events: u32, arg_reset: bool, arg_timeout: c.k_timeout_t) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(u32, p.arch_syscall_invoke5(p.cast(arg_event), p.cast(arg_events), p.cast(arg_reset), _lo3, _hi3, c.K_SYSCALL_K_EVENT_WAIT_ALL));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_wait_all(arg_event, arg_events, arg_reset, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_EVENT_WAIT_ALL_SAFE, arity 5
pub fn k_event_wait_all_safe(arg_event: [*c]c.struct_k_event, arg_events: u32, arg_reset: bool, arg_timeout: c.k_timeout_t) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(u32, p.arch_syscall_invoke5(p.cast(arg_event), p.cast(arg_events), p.cast(arg_reset), _lo3, _hi3, c.K_SYSCALL_K_EVENT_WAIT_ALL_SAFE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_wait_all_safe(arg_event, arg_events, arg_reset, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_EVENT_WAIT_SAFE, arity 5
pub fn k_event_wait_safe(arg_event: [*c]c.struct_k_event, arg_events: u32, arg_reset: bool, arg_timeout: c.k_timeout_t) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(u32, p.arch_syscall_invoke5(p.cast(arg_event), p.cast(arg_events), p.cast(arg_reset), _lo3, _hi3, c.K_SYSCALL_K_EVENT_WAIT_SAFE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_event_wait_safe(arg_event, arg_events, arg_reset, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_FLOAT_DISABLE, arity 1
pub fn k_float_disable(arg_thread: [*c]c.struct_k_thread) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_FLOAT_DISABLE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_float_disable(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_FLOAT_ENABLE, arity 2
pub fn k_float_enable(arg_thread: [*c]c.struct_k_thread, arg_options: c_uint) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_options), c.K_SYSCALL_K_FLOAT_ENABLE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_float_enable(arg_thread, arg_options);
}

/// kernel.h :: K_SYSCALL_K_FUTEX_WAIT, arity 4
pub fn k_futex_wait(arg_futex: [*c]c.struct_k_futex, arg_expected: c_int, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_futex), p.cast(arg_expected), _lo2, _hi2, c.K_SYSCALL_K_FUTEX_WAIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_futex_wait(arg_futex, arg_expected, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_FUTEX_WAKE, arity 2
pub fn k_futex_wake(arg_futex: [*c]c.struct_k_futex, arg_wake_all: bool) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_futex), p.cast(arg_wake_all), c.K_SYSCALL_K_FUTEX_WAKE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_futex_wake(arg_futex, arg_wake_all);
}

/// kernel.h :: K_SYSCALL_K_IS_PREEMPT_THREAD, arity 0
pub fn k_is_preempt_thread() c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke0(c.K_SYSCALL_K_IS_PREEMPT_THREAD));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_is_preempt_thread();
}

/// kernel.h :: K_SYSCALL_K_MSGQ_ALLOC_INIT, arity 3
pub fn k_msgq_alloc_init(arg_msgq: [*c]c.struct_k_msgq, arg_msg_size: usize, arg_max_msgs: u32) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_msgq), p.cast(arg_msg_size), p.cast(arg_max_msgs), c.K_SYSCALL_K_MSGQ_ALLOC_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_alloc_init(arg_msgq, arg_msg_size, arg_max_msgs);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_GET, arity 4
pub fn k_msgq_get(arg_msgq: [*c]c.struct_k_msgq, arg_data: ?*anyopaque, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_msgq), p.cast(arg_data), _lo2, _hi2, c.K_SYSCALL_K_MSGQ_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_get(arg_msgq, arg_data, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_GET_ATTRS, arity 2
pub fn k_msgq_get_attrs(arg_msgq: [*c]c.struct_k_msgq, arg_attrs: [*c]c.struct_k_msgq_attrs) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_msgq), p.cast(arg_attrs), c.K_SYSCALL_K_MSGQ_GET_ATTRS);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_msgq_get_attrs(arg_msgq, arg_attrs);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_NUM_FREE_GET, arity 1
pub fn k_msgq_num_free_get(arg_msgq: [*c]c.struct_k_msgq) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke1(p.cast(arg_msgq), c.K_SYSCALL_K_MSGQ_NUM_FREE_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_num_free_get(arg_msgq);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_NUM_USED_GET, arity 1
pub fn k_msgq_num_used_get(arg_msgq: [*c]c.struct_k_msgq) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke1(p.cast(arg_msgq), c.K_SYSCALL_K_MSGQ_NUM_USED_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_num_used_get(arg_msgq);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_PEEK, arity 2
pub fn k_msgq_peek(arg_msgq: [*c]c.struct_k_msgq, arg_data: ?*anyopaque) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_msgq), p.cast(arg_data), c.K_SYSCALL_K_MSGQ_PEEK));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_peek(arg_msgq, arg_data);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_PEEK_AT, arity 3
pub fn k_msgq_peek_at(arg_msgq: [*c]c.struct_k_msgq, arg_data: ?*anyopaque, arg_idx: u32) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_msgq), p.cast(arg_data), p.cast(arg_idx), c.K_SYSCALL_K_MSGQ_PEEK_AT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_peek_at(arg_msgq, arg_data, arg_idx);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_PURGE, arity 1
pub fn k_msgq_purge(arg_msgq: [*c]c.struct_k_msgq) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_msgq), c.K_SYSCALL_K_MSGQ_PURGE);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_msgq_purge(arg_msgq);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_PUT, arity 4
pub fn k_msgq_put(arg_msgq: [*c]c.struct_k_msgq, arg_data: ?*const anyopaque, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_msgq), p.cast(arg_data), _lo2, _hi2, c.K_SYSCALL_K_MSGQ_PUT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_put(arg_msgq, arg_data, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_MSGQ_PUT_FRONT, arity 2
pub fn k_msgq_put_front(arg_msgq: [*c]c.struct_k_msgq, arg_data: ?*const anyopaque) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_msgq), p.cast(arg_data), c.K_SYSCALL_K_MSGQ_PUT_FRONT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_msgq_put_front(arg_msgq, arg_data);
}

/// kernel.h :: K_SYSCALL_K_MUTEX_INIT, arity 1
pub fn k_mutex_init(arg_mutex: [*c]c.struct_k_mutex) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_mutex), c.K_SYSCALL_K_MUTEX_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_mutex_init(arg_mutex);
}

/// kernel.h :: K_SYSCALL_K_MUTEX_LOCK, arity 3
pub fn k_mutex_lock(arg_mutex: [*c]c.struct_k_mutex, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s1: u64 = @bitCast(arg_timeout.ticks);
            const _lo1: usize = @truncate(_s1);
            const _hi1: usize = @truncate(_s1 >> 32);
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_mutex), _lo1, _hi1, c.K_SYSCALL_K_MUTEX_LOCK));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_mutex_lock(arg_mutex, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_MUTEX_UNLOCK, arity 1
pub fn k_mutex_unlock(arg_mutex: [*c]c.struct_k_mutex) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_mutex), c.K_SYSCALL_K_MUTEX_UNLOCK));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_mutex_unlock(arg_mutex);
}

/// kobject.h :: K_SYSCALL_K_OBJECT_ACCESS_GRANT, arity 2
pub fn k_object_access_grant(arg_object: ?*const anyopaque, arg_thread: [*c]c.struct_k_thread) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_object), p.cast(arg_thread), c.K_SYSCALL_K_OBJECT_ACCESS_GRANT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_object_access_grant(arg_object, arg_thread);
}

/// kobject.h :: K_SYSCALL_K_OBJECT_ALLOC, arity 1
pub fn k_object_alloc(arg_otype: c.enum_k_objects) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke1(p.cast(arg_otype), c.K_SYSCALL_K_OBJECT_ALLOC));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_object_alloc(arg_otype);
}

/// kobject.h :: K_SYSCALL_K_OBJECT_ALLOC_SIZE, arity 2
pub fn k_object_alloc_size(arg_otype: c.enum_k_objects, arg_size: usize) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke2(p.cast(arg_otype), p.cast(arg_size), c.K_SYSCALL_K_OBJECT_ALLOC_SIZE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_object_alloc_size(arg_otype, arg_size);
}

/// kobject.h :: K_SYSCALL_K_OBJECT_RELEASE, arity 1
pub fn k_object_release(arg_object: ?*const anyopaque) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_object), c.K_SYSCALL_K_OBJECT_RELEASE);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_object_release(arg_object);
}

/// kernel.h :: K_SYSCALL_K_PIPE_CLOSE, arity 1
pub fn k_pipe_close(arg_pipe: [*c]c.struct_k_pipe) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_pipe), c.K_SYSCALL_K_PIPE_CLOSE);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_pipe_close(arg_pipe);
}

/// kernel.h :: K_SYSCALL_K_PIPE_INIT, arity 3
pub fn k_pipe_init(arg_pipe: [*c]c.struct_k_pipe, arg_buffer: [*c]u8, arg_buffer_size: usize) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke3(p.cast(arg_pipe), p.cast(arg_buffer), p.cast(arg_buffer_size), c.K_SYSCALL_K_PIPE_INIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_pipe_init(arg_pipe, arg_buffer, arg_buffer_size);
}

/// kernel.h :: K_SYSCALL_K_PIPE_READ, arity 5
pub fn k_pipe_read(arg_pipe: [*c]c.struct_k_pipe, arg_data: [*c]u8, arg_len: usize, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(c_int, p.arch_syscall_invoke5(p.cast(arg_pipe), p.cast(arg_data), p.cast(arg_len), _lo3, _hi3, c.K_SYSCALL_K_PIPE_READ));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_pipe_read(arg_pipe, arg_data, arg_len, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_PIPE_RESET, arity 1
pub fn k_pipe_reset(arg_pipe: [*c]c.struct_k_pipe) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_pipe), c.K_SYSCALL_K_PIPE_RESET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_pipe_reset(arg_pipe);
}

/// kernel.h :: K_SYSCALL_K_PIPE_WRITE, arity 5
pub fn k_pipe_write(arg_pipe: [*c]c.struct_k_pipe, arg_data: [*c]const u8, arg_len: usize, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s3: u64 = @bitCast(arg_timeout.ticks);
            const _lo3: usize = @truncate(_s3);
            const _hi3: usize = @truncate(_s3 >> 32);
            return p.from(c_int, p.arch_syscall_invoke5(p.cast(arg_pipe), p.cast(arg_data), p.cast(arg_len), _lo3, _hi3, c.K_SYSCALL_K_PIPE_WRITE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_pipe_write(arg_pipe, arg_data, arg_len, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_POLL, arity 4
pub fn k_poll(arg_events: ?*c.struct_k_poll_event, arg_num_events: c_int, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_events), p.cast(arg_num_events), _lo2, _hi2, c.K_SYSCALL_K_POLL));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_poll(arg_events, arg_num_events, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_POLL_SIGNAL_CHECK, arity 3
pub fn k_poll_signal_check(arg_sig: [*c]c.struct_k_poll_signal, arg_signaled: [*c]c_uint, arg_result: [*c]c_int) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke3(p.cast(arg_sig), p.cast(arg_signaled), p.cast(arg_result), c.K_SYSCALL_K_POLL_SIGNAL_CHECK);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_poll_signal_check(arg_sig, arg_signaled, arg_result);
}

/// kernel.h :: K_SYSCALL_K_POLL_SIGNAL_INIT, arity 1
pub fn k_poll_signal_init(arg_sig: [*c]c.struct_k_poll_signal) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_sig), c.K_SYSCALL_K_POLL_SIGNAL_INIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_poll_signal_init(arg_sig);
}

/// kernel.h :: K_SYSCALL_K_POLL_SIGNAL_RAISE, arity 2
pub fn k_poll_signal_raise(arg_sig: [*c]c.struct_k_poll_signal, arg_result: c_int) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_sig), p.cast(arg_result), c.K_SYSCALL_K_POLL_SIGNAL_RAISE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_poll_signal_raise(arg_sig, arg_result);
}

/// kernel.h :: K_SYSCALL_K_POLL_SIGNAL_RESET, arity 1
pub fn k_poll_signal_reset(arg_sig: [*c]c.struct_k_poll_signal) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_sig), c.K_SYSCALL_K_POLL_SIGNAL_RESET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_poll_signal_reset(arg_sig);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_ALLOC_APPEND, arity 2
pub fn k_queue_alloc_append(arg_queue: [*c]c.struct_k_queue, arg_data: ?*anyopaque) i32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(i32, p.arch_syscall_invoke2(p.cast(arg_queue), p.cast(arg_data), c.K_SYSCALL_K_QUEUE_ALLOC_APPEND));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_alloc_append(arg_queue, arg_data);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_ALLOC_PREPEND, arity 2
pub fn k_queue_alloc_prepend(arg_queue: [*c]c.struct_k_queue, arg_data: ?*anyopaque) i32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(i32, p.arch_syscall_invoke2(p.cast(arg_queue), p.cast(arg_data), c.K_SYSCALL_K_QUEUE_ALLOC_PREPEND));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_alloc_prepend(arg_queue, arg_data);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_CANCEL_WAIT, arity 1
pub fn k_queue_cancel_wait(arg_queue: [*c]c.struct_k_queue) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_queue), c.K_SYSCALL_K_QUEUE_CANCEL_WAIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_queue_cancel_wait(arg_queue);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_GET, arity 3
pub fn k_queue_get(arg_queue: [*c]c.struct_k_queue, arg_timeout: c.k_timeout_t) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s1: u64 = @bitCast(arg_timeout.ticks);
            const _lo1: usize = @truncate(_s1);
            const _hi1: usize = @truncate(_s1 >> 32);
            return p.from(?*anyopaque, p.arch_syscall_invoke3(p.cast(arg_queue), _lo1, _hi1, c.K_SYSCALL_K_QUEUE_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_get(arg_queue, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_INIT, arity 1
pub fn k_queue_init(arg_queue: [*c]c.struct_k_queue) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_queue), c.K_SYSCALL_K_QUEUE_INIT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_queue_init(arg_queue);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_IS_EMPTY, arity 1
pub fn k_queue_is_empty(arg_queue: [*c]c.struct_k_queue) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_queue), c.K_SYSCALL_K_QUEUE_IS_EMPTY));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_is_empty(arg_queue);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_PEEK_HEAD, arity 1
pub fn k_queue_peek_head(arg_queue: [*c]c.struct_k_queue) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke1(p.cast(arg_queue), c.K_SYSCALL_K_QUEUE_PEEK_HEAD));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_peek_head(arg_queue);
}

/// kernel.h :: K_SYSCALL_K_QUEUE_PEEK_TAIL, arity 1
pub fn k_queue_peek_tail(arg_queue: [*c]c.struct_k_queue) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke1(p.cast(arg_queue), c.K_SYSCALL_K_QUEUE_PEEK_TAIL));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_queue_peek_tail(arg_queue);
}

/// kernel.h :: K_SYSCALL_K_RESCHEDULE, arity 0
pub fn k_reschedule() void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke0(c.K_SYSCALL_K_RESCHEDULE);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_reschedule();
}

/// kernel.h :: K_SYSCALL_K_SCHED_CURRENT_THREAD_QUERY, arity 0
pub fn k_sched_current_thread_query() c.k_tid_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c.k_tid_t, p.arch_syscall_invoke0(c.K_SYSCALL_K_SCHED_CURRENT_THREAD_QUERY));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_sched_current_thread_query();
}

/// kernel.h :: K_SYSCALL_K_SEM_COUNT_GET, arity 1
pub fn k_sem_count_get(arg_sem: [*c]c.struct_k_sem) c_uint {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_uint, p.arch_syscall_invoke1(p.cast(arg_sem), c.K_SYSCALL_K_SEM_COUNT_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_sem_count_get(arg_sem);
}

/// kernel.h :: K_SYSCALL_K_SEM_GIVE, arity 1
pub fn k_sem_give(arg_sem: [*c]c.struct_k_sem) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_sem), c.K_SYSCALL_K_SEM_GIVE);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_sem_give(arg_sem);
}

/// kernel.h :: K_SYSCALL_K_SEM_INIT, arity 3
pub fn k_sem_init(arg_sem: [*c]c.struct_k_sem, arg_initial_count: c_uint, arg_limit: c_uint) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_sem), p.cast(arg_initial_count), p.cast(arg_limit), c.K_SYSCALL_K_SEM_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_sem_init(arg_sem, arg_initial_count, arg_limit);
}

/// kernel.h :: K_SYSCALL_K_SEM_RESET, arity 1
pub fn k_sem_reset(arg_sem: [*c]c.struct_k_sem) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_sem), c.K_SYSCALL_K_SEM_RESET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_sem_reset(arg_sem);
}

/// kernel.h :: K_SYSCALL_K_SEM_TAKE, arity 3
pub fn k_sem_take(arg_sem: [*c]c.struct_k_sem, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s1: u64 = @bitCast(arg_timeout.ticks);
            const _lo1: usize = @truncate(_s1);
            const _hi1: usize = @truncate(_s1 >> 32);
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_sem), _lo1, _hi1, c.K_SYSCALL_K_SEM_TAKE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_sem_take(arg_sem, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_SLEEP, arity 2
pub fn k_sleep(arg_timeout: c.k_timeout_t) i32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s0: u64 = @bitCast(arg_timeout.ticks);
            const _lo0: usize = @truncate(_s0);
            const _hi0: usize = @truncate(_s0 >> 32);
            return p.from(i32, p.arch_syscall_invoke2(_lo0, _hi0, c.K_SYSCALL_K_SLEEP));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_sleep(arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_STACK_ALLOC_INIT, arity 2
pub fn k_stack_alloc_init(arg_stack: [*c]c.struct_k_stack, arg_num_entries: u32) i32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(i32, p.arch_syscall_invoke2(p.cast(arg_stack), p.cast(arg_num_entries), c.K_SYSCALL_K_STACK_ALLOC_INIT));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_stack_alloc_init(arg_stack, arg_num_entries);
}

/// kernel.h :: K_SYSCALL_K_STACK_POP, arity 4
pub fn k_stack_pop(arg_stack: [*c]c.struct_k_stack, arg_data: [*c]c.stack_data_t, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s2: u64 = @bitCast(arg_timeout.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_stack), p.cast(arg_data), _lo2, _hi2, c.K_SYSCALL_K_STACK_POP));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_stack_pop(arg_stack, arg_data, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_STACK_PUSH, arity 2
pub fn k_stack_push(arg_stack: [*c]c.struct_k_stack, arg_data: c.stack_data_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_stack), p.cast(arg_data), c.K_SYSCALL_K_STACK_PUSH));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_stack_push(arg_stack, arg_data);
}

/// kernel.h :: K_SYSCALL_K_STR_OUT, arity 2
pub fn k_str_out(arg_c: [*c]u8, arg_n: usize) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_c), p.cast(arg_n), c.K_SYSCALL_K_STR_OUT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_str_out(arg_c, arg_n);
}

/// kernel.h :: K_SYSCALL_K_THREAD_ABORT, arity 1
pub fn k_thread_abort(arg_thread: c.k_tid_t) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_THREAD_ABORT);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_abort(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_ABSOLUTE_DEADLINE_SET, arity 2
pub fn k_thread_absolute_deadline_set(arg_thread: c.k_tid_t, arg_deadline: c_int) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_deadline), c.K_SYSCALL_K_THREAD_ABSOLUTE_DEADLINE_SET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_absolute_deadline_set(arg_thread, arg_deadline);
}

/// kernel.h :: K_SYSCALL_K_THREAD_CREATE, arity 6
pub fn k_thread_create(arg_new_thread: [*c]c.struct_k_thread, arg_stack: [*c]c.k_thread_stack_t, arg_stack_size: usize, arg_entry: c.k_thread_entry_t, arg_p1: ?*anyopaque, arg_p2: ?*anyopaque, arg_p3: ?*anyopaque, arg_prio: c_int, arg_options: u32, arg_delay: c.k_timeout_t) c.k_tid_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s9: u64 = @bitCast(arg_delay.ticks);
            const _lo9: usize = @truncate(_s9);
            const _hi9: usize = @truncate(_s9 >> 32);
            const _more = [_]usize{ p.cast(arg_p2), p.cast(arg_p3), p.cast(arg_prio), p.cast(arg_options), _lo9, _hi9 };
            return p.from(c.k_tid_t, p.arch_syscall_invoke6(p.cast(arg_new_thread), p.cast(arg_stack), p.cast(arg_stack_size), p.cast(arg_entry), p.cast(arg_p1), @intFromPtr(&_more), c.K_SYSCALL_K_THREAD_CREATE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_create(arg_new_thread, arg_stack, arg_stack_size, arg_entry, arg_p1, arg_p2, arg_p3, arg_prio, arg_options, arg_delay);
}

/// kernel.h :: K_SYSCALL_K_THREAD_CUSTOM_DATA_GET, arity 0
pub fn k_thread_custom_data_get() ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke0(c.K_SYSCALL_K_THREAD_CUSTOM_DATA_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_custom_data_get();
}

/// kernel.h :: K_SYSCALL_K_THREAD_CUSTOM_DATA_SET, arity 1
pub fn k_thread_custom_data_set(arg_value: ?*anyopaque) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_value), c.K_SYSCALL_K_THREAD_CUSTOM_DATA_SET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_custom_data_set(arg_value);
}

/// kernel.h :: K_SYSCALL_K_THREAD_DEADLINE_SET, arity 2
pub fn k_thread_deadline_set(arg_thread: c.k_tid_t, arg_deadline: c_int) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_deadline), c.K_SYSCALL_K_THREAD_DEADLINE_SET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_deadline_set(arg_thread, arg_deadline);
}

/// kernel.h :: K_SYSCALL_K_THREAD_JOIN, arity 3
pub fn k_thread_join(arg_thread: [*c]c.struct_k_thread, arg_timeout: c.k_timeout_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s1: u64 = @bitCast(arg_timeout.ticks);
            const _lo1: usize = @truncate(_s1);
            const _hi1: usize = @truncate(_s1 >> 32);
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_thread), _lo1, _hi1, c.K_SYSCALL_K_THREAD_JOIN));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_join(arg_thread, arg_timeout);
}

/// kernel.h :: K_SYSCALL_K_THREAD_NAME_COPY, arity 3
pub fn k_thread_name_copy(arg_thread: c.k_tid_t, arg_buf: [*c]u8, arg_size: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_thread), p.cast(arg_buf), p.cast(arg_size), c.K_SYSCALL_K_THREAD_NAME_COPY));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_name_copy(arg_thread, arg_buf, arg_size);
}

/// kernel.h :: K_SYSCALL_K_THREAD_NAME_SET, arity 2
pub fn k_thread_name_set(arg_thread: c.k_tid_t, arg_str: [*c]const u8) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_str), c.K_SYSCALL_K_THREAD_NAME_SET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_name_set(arg_thread, arg_str);
}

/// kernel.h :: K_SYSCALL_K_THREAD_PRIORITY_GET, arity 1
pub fn k_thread_priority_get(arg_thread: c.k_tid_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_THREAD_PRIORITY_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_priority_get(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_PRIORITY_SET, arity 2
pub fn k_thread_priority_set(arg_thread: c.k_tid_t, arg_prio: c_int) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_prio), c.K_SYSCALL_K_THREAD_PRIORITY_SET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_priority_set(arg_thread, arg_prio);
}

/// kernel.h :: K_SYSCALL_K_THREAD_RESUME, arity 1
pub fn k_thread_resume(arg_thread: c.k_tid_t) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_THREAD_RESUME);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_resume(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_GET, arity 1
pub fn k_thread_runtime_stack_unused_threshold_get(arg_thread: [*c]c.struct_k_thread) usize {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(usize, p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_runtime_stack_unused_threshold_get(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_PCT_SET, arity 2
pub fn k_thread_runtime_stack_unused_threshold_pct_set(arg_thread: [*c]c.struct_k_thread, arg_pct: u32) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_pct), c.K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_PCT_SET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_runtime_stack_unused_threshold_pct_set(arg_thread, arg_pct);
}

/// kernel.h :: K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_SET, arity 2
pub fn k_thread_runtime_stack_unused_threshold_set(arg_thread: [*c]c.struct_k_thread, arg_threshold: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_threshold), c.K_SYSCALL_K_THREAD_RUNTIME_STACK_UNUSED_THRESHOLD_SET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_runtime_stack_unused_threshold_set(arg_thread, arg_threshold);
}

/// kernel.h :: K_SYSCALL_K_THREAD_STACK_ALLOC, arity 2
pub fn k_thread_stack_alloc(arg_size: usize, arg_flags: c_int) [*c]c.k_thread_stack_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from([*c]c.k_thread_stack_t, p.arch_syscall_invoke2(p.cast(arg_size), p.cast(arg_flags), c.K_SYSCALL_K_THREAD_STACK_ALLOC));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_stack_alloc(arg_size, arg_flags);
}

/// kernel.h :: K_SYSCALL_K_THREAD_STACK_FREE, arity 1
pub fn k_thread_stack_free(arg_stack: [*c]c.k_thread_stack_t) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke1(p.cast(arg_stack), c.K_SYSCALL_K_THREAD_STACK_FREE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_stack_free(arg_stack);
}

/// kernel.h :: K_SYSCALL_K_THREAD_STACK_SPACE_GET, arity 2
pub fn k_thread_stack_space_get(arg_thread: [*c]const c.struct_k_thread, arg_unused_ptr: [*c]usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_thread), p.cast(arg_unused_ptr), c.K_SYSCALL_K_THREAD_STACK_SPACE_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_stack_space_get(arg_thread, arg_unused_ptr);
}

/// kernel.h :: K_SYSCALL_K_THREAD_SUSPEND, arity 1
pub fn k_thread_suspend(arg_thread: c.k_tid_t) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_THREAD_SUSPEND);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_thread_suspend(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_TIMEOUT_EXPIRES_TICKS, arity 2
pub fn k_thread_timeout_expires_ticks(arg_thread: [*c]const c.struct_k_thread) c.k_ticks_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            var _ret64: u64 = undefined;
            _ = p.arch_syscall_invoke2(p.cast(arg_thread), @intFromPtr(&_ret64), c.K_SYSCALL_K_THREAD_TIMEOUT_EXPIRES_TICKS);
            return @bitCast(_ret64);
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_timeout_expires_ticks(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_THREAD_TIMEOUT_REMAINING_TICKS, arity 2
pub fn k_thread_timeout_remaining_ticks(arg_thread: [*c]const c.struct_k_thread) c.k_ticks_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            var _ret64: u64 = undefined;
            _ = p.arch_syscall_invoke2(p.cast(arg_thread), @intFromPtr(&_ret64), c.K_SYSCALL_K_THREAD_TIMEOUT_REMAINING_TICKS);
            return @bitCast(_ret64);
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_thread_timeout_remaining_ticks(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_TIMER_EXPIRES_TICKS, arity 2
pub fn k_timer_expires_ticks(arg_timer: [*c]const c.struct_k_timer) c.k_ticks_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            var _ret64: u64 = undefined;
            _ = p.arch_syscall_invoke2(p.cast(arg_timer), @intFromPtr(&_ret64), c.K_SYSCALL_K_TIMER_EXPIRES_TICKS);
            return @bitCast(_ret64);
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_timer_expires_ticks(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_REMAINING_TICKS, arity 2
pub fn k_timer_remaining_ticks(arg_timer: [*c]const c.struct_k_timer) c.k_ticks_t {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            var _ret64: u64 = undefined;
            _ = p.arch_syscall_invoke2(p.cast(arg_timer), @intFromPtr(&_ret64), c.K_SYSCALL_K_TIMER_REMAINING_TICKS);
            return @bitCast(_ret64);
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_timer_remaining_ticks(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_START, arity 5
pub fn k_timer_start(arg_timer: [*c]c.struct_k_timer, arg_duration: c.k_timeout_t, arg_period: c.k_timeout_t) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            const _s1: u64 = @bitCast(arg_duration.ticks);
            const _lo1: usize = @truncate(_s1);
            const _hi1: usize = @truncate(_s1 >> 32);
            const _s2: u64 = @bitCast(arg_period.ticks);
            const _lo2: usize = @truncate(_s2);
            const _hi2: usize = @truncate(_s2 >> 32);
            _ = p.arch_syscall_invoke5(p.cast(arg_timer), _lo1, _hi1, _lo2, _hi2, c.K_SYSCALL_K_TIMER_START);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_timer_start(arg_timer, arg_duration, arg_period);
}

/// kernel.h :: K_SYSCALL_K_TIMER_STATUS_GET, arity 1
pub fn k_timer_status_get(arg_timer: [*c]c.struct_k_timer) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke1(p.cast(arg_timer), c.K_SYSCALL_K_TIMER_STATUS_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_timer_status_get(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_STATUS_SYNC, arity 1
pub fn k_timer_status_sync(arg_timer: [*c]c.struct_k_timer) u32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(u32, p.arch_syscall_invoke1(p.cast(arg_timer), c.K_SYSCALL_K_TIMER_STATUS_SYNC));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_timer_status_sync(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_STOP, arity 1
pub fn k_timer_stop(arg_timer: [*c]c.struct_k_timer) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_timer), c.K_SYSCALL_K_TIMER_STOP);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_timer_stop(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_USER_DATA_GET, arity 1
pub fn k_timer_user_data_get(arg_timer: [*c]const c.struct_k_timer) ?*anyopaque {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(?*anyopaque, p.arch_syscall_invoke1(p.cast(arg_timer), c.K_SYSCALL_K_TIMER_USER_DATA_GET));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_timer_user_data_get(arg_timer);
}

/// kernel.h :: K_SYSCALL_K_TIMER_USER_DATA_SET, arity 2
pub fn k_timer_user_data_set(arg_timer: [*c]c.struct_k_timer, arg_user_data: ?*anyopaque) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke2(p.cast(arg_timer), p.cast(arg_user_data), c.K_SYSCALL_K_TIMER_USER_DATA_SET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_timer_user_data_set(arg_timer, arg_user_data);
}

/// kernel.h :: K_SYSCALL_K_UPTIME_TICKS, arity 1
pub fn k_uptime_ticks() i64 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            var _ret64: u64 = undefined;
            _ = p.arch_syscall_invoke1(@intFromPtr(&_ret64), c.K_SYSCALL_K_UPTIME_TICKS);
            return @bitCast(_ret64);
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_uptime_ticks();
}

/// kernel.h :: K_SYSCALL_K_USLEEP, arity 1
pub fn k_usleep(arg_us: i32) i32 {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(i32, p.arch_syscall_invoke1(p.cast(arg_us), c.K_SYSCALL_K_USLEEP));
        }
    }
    p.compiler_barrier();
    return c.z_impl_k_usleep(arg_us);
}

/// kernel.h :: K_SYSCALL_K_WAKEUP, arity 1
pub fn k_wakeup(arg_thread: c.k_tid_t) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_thread), c.K_SYSCALL_K_WAKEUP);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_wakeup(arg_thread);
}

/// kernel.h :: K_SYSCALL_K_YIELD, arity 0
pub fn k_yield() void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke0(c.K_SYSCALL_K_YIELD);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_k_yield();
}

/// app_api.h :: K_SYSCALL_PUBLISH, arity 3
pub fn publish(arg_channel: c.enum_Channels, arg_data: ?*anyopaque, arg_data_len: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_channel), p.cast(arg_data), p.cast(arg_data_len), c.K_SYSCALL_PUBLISH));
        }
    }
    p.compiler_barrier();
    return c.z_impl_publish(arg_channel, arg_data, arg_data_len);
}

/// app_api.h :: K_SYSCALL_RECEIVE, arity 3
pub fn receive(arg_channel: c.enum_Channels, arg_data: ?*anyopaque, arg_data_len: usize) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke3(p.cast(arg_channel), p.cast(arg_data), p.cast(arg_data_len), c.K_SYSCALL_RECEIVE));
        }
    }
    p.compiler_barrier();
    return c.z_impl_receive(arg_channel, arg_data, arg_data_len);
}

/// app_api.h :: K_SYSCALL_REGISTER_SUBSCRIBER, arity 2
pub fn register_subscriber(arg_channel: c.enum_Channels, arg_evt: [*c]c.struct_k_event) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_channel), p.cast(arg_evt), c.K_SYSCALL_REGISTER_SUBSCRIBER));
        }
    }
    p.compiler_barrier();
    return c.z_impl_register_subscriber(arg_channel, arg_evt);
}

/// clock.h :: K_SYSCALL_SYS_CLOCK_GETRTOFFSET, arity 1
pub fn sys_clock_getrtoffset(arg_tp: ?*c.struct_timespec) void {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            _ = p.arch_syscall_invoke1(p.cast(arg_tp), c.K_SYSCALL_SYS_CLOCK_GETRTOFFSET);
            return;
        }
    }
    p.compiler_barrier();
    c.z_impl_sys_clock_getrtoffset(arg_tp);
}

/// clock.h :: K_SYSCALL_SYS_CLOCK_NANOSLEEP, arity 4
pub fn sys_clock_nanosleep(arg_clock_id: c_int, arg_flags: c_int, arg_rqtp: ?*const c.struct_timespec, arg_rmtp: ?*c.struct_timespec) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke4(p.cast(arg_clock_id), p.cast(arg_flags), p.cast(arg_rqtp), p.cast(arg_rmtp), c.K_SYSCALL_SYS_CLOCK_NANOSLEEP));
        }
    }
    p.compiler_barrier();
    return c.z_impl_sys_clock_nanosleep(arg_clock_id, arg_flags, arg_rqtp, arg_rmtp);
}

/// clock.h :: K_SYSCALL_SYS_CLOCK_SETTIME, arity 2
pub fn sys_clock_settime(arg_clock_id: c_int, arg_tp: ?*const c.struct_timespec) c_int {
    if (comptime c.CONFIG_USERSPACE == 1) {
        if (p.z_syscall_trap()) {
            return p.from(c_int, p.arch_syscall_invoke2(p.cast(arg_clock_id), p.cast(arg_tp), c.K_SYSCALL_SYS_CLOCK_SETTIME));
        }
    }
    p.compiler_barrier();
    return c.z_impl_sys_clock_settime(arg_clock_id, arg_tp);
}
