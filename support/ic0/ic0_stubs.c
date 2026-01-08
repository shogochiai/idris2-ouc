/*
 * IC0 System API Stubs for idris2-cdk
 *
 * This file bridges idris2-cdk's %foreign "C:ic0_*,libic0" declarations
 * with actual WASM imports from the IC runtime.
 *
 * idris2-cdk expects: ic0_msg_reply() (C function)
 * IC runtime provides: ic0.msg_reply (WASM import)
 *
 * These stubs provide the C functions that wrap the WASM imports.
 */
#include <stdint.h>

/* =============================================================================
 * WASM Imports from IC Runtime
 * ============================================================================= */

/* Message reply */
extern void ic0_msg_reply_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_reply")));
extern void ic0_msg_reply_data_append_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_reply_data_append")));

/* Message arguments */
extern uint32_t ic0_msg_arg_data_size_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_arg_data_size")));
extern void ic0_msg_arg_data_copy_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_arg_data_copy")));

/* Caller information */
extern uint32_t ic0_msg_caller_size_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_caller_size")));
extern void ic0_msg_caller_copy_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_caller_copy")));

/* Message rejection */
extern void ic0_msg_reject_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_reject")));
extern uint32_t ic0_msg_reject_code_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_reject_code")));
extern uint32_t ic0_msg_reject_msg_size_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_reject_msg_size")));
extern void ic0_msg_reject_msg_copy_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_reject_msg_copy")));

/* Canister information */
extern uint32_t ic0_canister_self_size_impl(void)
    __attribute__((import_module("ic0"), import_name("canister_self_size")));
extern void ic0_canister_self_copy_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("canister_self_copy")));
extern void ic0_canister_cycle_balance128_impl(uint32_t dst)
    __attribute__((import_module("ic0"), import_name("canister_cycle_balance128")));
extern uint32_t ic0_canister_status_impl(void)
    __attribute__((import_module("ic0"), import_name("canister_status")));

/* Time */
extern uint64_t ic0_time_impl(void)
    __attribute__((import_module("ic0"), import_name("time")));

/* Stable memory */
extern uint32_t ic0_stable_size_impl(void)
    __attribute__((import_module("ic0"), import_name("stable_size")));
extern uint32_t ic0_stable_grow_impl(uint32_t new_pages)
    __attribute__((import_module("ic0"), import_name("stable_grow")));
extern void ic0_stable_read_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("stable_read")));
extern void ic0_stable_write_impl(uint32_t offset, uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("stable_write")));
extern uint64_t ic0_stable64_size_impl(void)
    __attribute__((import_module("ic0"), import_name("stable64_size")));
extern uint64_t ic0_stable64_grow_impl(uint64_t new_pages)
    __attribute__((import_module("ic0"), import_name("stable64_grow")));
extern void ic0_stable64_read_impl(uint64_t dst, uint64_t offset, uint64_t size)
    __attribute__((import_module("ic0"), import_name("stable64_read")));
extern void ic0_stable64_write_impl(uint64_t offset, uint64_t src, uint64_t size)
    __attribute__((import_module("ic0"), import_name("stable64_write")));

/* Certified data */
extern void ic0_certified_data_set_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("certified_data_set")));
extern uint32_t ic0_data_certificate_size_impl(void)
    __attribute__((import_module("ic0"), import_name("data_certificate_size")));
extern void ic0_data_certificate_copy_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("data_certificate_copy")));

/* Inter-canister calls */
extern void ic0_call_new_impl(uint32_t callee_src, uint32_t callee_size,
                               uint32_t name_src, uint32_t name_size,
                               uint32_t reply_fun, uint32_t reply_env,
                               uint32_t reject_fun, uint32_t reject_env)
    __attribute__((import_module("ic0"), import_name("call_new")));
extern void ic0_call_data_append_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("call_data_append")));
extern void ic0_call_cycles_add128_impl(uint64_t high, uint64_t low)
    __attribute__((import_module("ic0"), import_name("call_cycles_add128")));
extern uint32_t ic0_call_perform_impl(void)
    __attribute__((import_module("ic0"), import_name("call_perform")));

/* Cycles */
extern void ic0_msg_cycles_available128_impl(uint32_t dst)
    __attribute__((import_module("ic0"), import_name("msg_cycles_available128")));
extern void ic0_msg_cycles_accept128_impl(uint64_t max_high, uint64_t max_low, uint32_t dst)
    __attribute__((import_module("ic0"), import_name("msg_cycles_accept128")));
extern void ic0_msg_cycles_refunded128_impl(uint32_t dst)
    __attribute__((import_module("ic0"), import_name("msg_cycles_refunded128")));

/* Debugging */
extern void ic0_debug_print_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("debug_print")));
extern void ic0_trap_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("trap")));

/* Performance & timers */
extern uint64_t ic0_performance_counter_impl(uint32_t type)
    __attribute__((import_module("ic0"), import_name("performance_counter")));
extern uint64_t ic0_global_timer_set_impl(uint64_t timestamp)
    __attribute__((import_module("ic0"), import_name("global_timer_set")));
extern uint64_t ic0_instruction_counter_impl(void)
    __attribute__((import_module("ic0"), import_name("instruction_counter")));
extern uint32_t ic0_is_controller_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("is_controller")));

/* =============================================================================
 * C Stubs for idris2-cdk FFI
 * These match the %foreign "C:ic0_*,libic0" declarations in ICP.IC0
 * ============================================================================= */

/* Message reply */
void ic0_msg_reply(void) { ic0_msg_reply_impl(); }
void ic0_msg_reply_data_append(int32_t src, int32_t size) {
    ic0_msg_reply_data_append_impl((uint32_t)src, (uint32_t)size);
}

/* Message arguments */
int32_t ic0_msg_arg_data_size(void) { return (int32_t)ic0_msg_arg_data_size_impl(); }
void ic0_msg_arg_data_copy(int32_t dst, int32_t offset, int32_t size) {
    ic0_msg_arg_data_copy_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}

/* Caller information */
int32_t ic0_msg_caller_size(void) { return (int32_t)ic0_msg_caller_size_impl(); }
void ic0_msg_caller_copy(int32_t dst, int32_t offset, int32_t size) {
    ic0_msg_caller_copy_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}

/* Message rejection */
void ic0_msg_reject(int32_t src, int32_t size) {
    ic0_msg_reject_impl((uint32_t)src, (uint32_t)size);
}
int32_t ic0_msg_reject_code(void) { return (int32_t)ic0_msg_reject_code_impl(); }
int32_t ic0_msg_reject_msg_size(void) { return (int32_t)ic0_msg_reject_msg_size_impl(); }
void ic0_msg_reject_msg_copy(int32_t dst, int32_t offset, int32_t size) {
    ic0_msg_reject_msg_copy_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}

/* Canister information */
int32_t ic0_canister_self_size(void) { return (int32_t)ic0_canister_self_size_impl(); }
void ic0_canister_self_copy(int32_t dst, int32_t offset, int32_t size) {
    ic0_canister_self_copy_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}
void ic0_canister_cycle_balance128(int32_t dst) {
    ic0_canister_cycle_balance128_impl((uint32_t)dst);
}
int32_t ic0_canister_status(void) { return (int32_t)ic0_canister_status_impl(); }

/* Time */
uint64_t ic0_time(void) { return ic0_time_impl(); }

/* Stable memory */
int32_t ic0_stable_size(void) { return (int32_t)ic0_stable_size_impl(); }
int32_t ic0_stable_grow(int32_t new_pages) {
    return (int32_t)ic0_stable_grow_impl((uint32_t)new_pages);
}
void ic0_stable_read(int32_t dst, int32_t offset, int32_t size) {
    ic0_stable_read_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}
void ic0_stable_write(int32_t offset, int32_t src, int32_t size) {
    ic0_stable_write_impl((uint32_t)offset, (uint32_t)src, (uint32_t)size);
}
uint64_t ic0_stable64_size(void) { return ic0_stable64_size_impl(); }
uint64_t ic0_stable64_grow(uint64_t new_pages) { return ic0_stable64_grow_impl(new_pages); }
void ic0_stable64_read(uint64_t dst, uint64_t offset, uint64_t size) {
    ic0_stable64_read_impl(dst, offset, size);
}
void ic0_stable64_write(uint64_t offset, uint64_t src, uint64_t size) {
    ic0_stable64_write_impl(offset, src, size);
}

/* Certified data */
void ic0_certified_data_set(int32_t src, int32_t size) {
    ic0_certified_data_set_impl((uint32_t)src, (uint32_t)size);
}
int32_t ic0_data_certificate_size(void) { return (int32_t)ic0_data_certificate_size_impl(); }
void ic0_data_certificate_copy(int32_t dst, int32_t offset, int32_t size) {
    ic0_data_certificate_copy_impl((uint32_t)dst, (uint32_t)offset, (uint32_t)size);
}

/* Inter-canister calls */
void ic0_call_new(int32_t callee_src, int32_t callee_size,
                  int32_t name_src, int32_t name_size,
                  int32_t reply_fun, int32_t reply_env,
                  int32_t reject_fun, int32_t reject_env) {
    ic0_call_new_impl((uint32_t)callee_src, (uint32_t)callee_size,
                      (uint32_t)name_src, (uint32_t)name_size,
                      (uint32_t)reply_fun, (uint32_t)reply_env,
                      (uint32_t)reject_fun, (uint32_t)reject_env);
}
void ic0_call_data_append(int32_t src, int32_t size) {
    ic0_call_data_append_impl((uint32_t)src, (uint32_t)size);
}
void ic0_call_cycles_add128(uint64_t high, uint64_t low) {
    ic0_call_cycles_add128_impl(high, low);
}
int32_t ic0_call_perform(void) { return (int32_t)ic0_call_perform_impl(); }

/* Cycles */
void ic0_msg_cycles_available128(int32_t dst) {
    ic0_msg_cycles_available128_impl((uint32_t)dst);
}
void ic0_msg_cycles_accept128(uint64_t max_high, uint64_t max_low, int32_t dst) {
    ic0_msg_cycles_accept128_impl(max_high, max_low, (uint32_t)dst);
}
void ic0_msg_cycles_refunded128(int32_t dst) {
    ic0_msg_cycles_refunded128_impl((uint32_t)dst);
}

/* Debugging */
void ic0_debug_print(int32_t src, int32_t size) {
    ic0_debug_print_impl((uint32_t)src, (uint32_t)size);
}
void ic0_trap(int32_t src, int32_t size) {
    ic0_trap_impl((uint32_t)src, (uint32_t)size);
}

/* Performance & timers */
uint64_t ic0_performance_counter(int32_t type) {
    return ic0_performance_counter_impl((uint32_t)type);
}
uint64_t ic0_global_timer_set(uint64_t timestamp) {
    return ic0_global_timer_set_impl(timestamp);
}
uint64_t ic0_instruction_counter(void) { return ic0_instruction_counter_impl(); }
int32_t ic0_is_controller(int32_t src, int32_t size) {
    return (int32_t)ic0_is_controller_impl((uint32_t)src, (uint32_t)size);
}

/* =============================================================================
 * OUC FFI Bridge
 * These enable communication between C (canister_entry.c) and Idris2 (Main.idr)
 * Note: Idris2 Int is 64-bit, so we accept int64_t and truncate/extend as needed
 * ============================================================================= */

/* Global variables for C<->Idris2 communication */
static int32_t ouc_result_i32 = 0;
static int32_t ouc_arg_i32[8] = {0};  /* Up to 8 int32 args */
static int32_t ouc_state_initialized = 0;  /* Persistent state flag */
static int32_t ouc_auditor_count = 0;  /* Persistent auditor count */

/* Called from Idris2 via %foreign to set result (Idris2 Int -> int64_t) */
void ouc_set_result_i32(int64_t value) {
    ouc_result_i32 = (int32_t)value;
}

/* Called from Idris2 via %foreign to get argument (returns Idris2 Int) */
int64_t ouc_get_arg_i32(int64_t index) {
    int64_t result = 0;
    if (index >= 0 && index < 8) {
        result = (int64_t)ouc_arg_i32[(int32_t)index];
    }
    /* Debug: log the argument being read */
    char buf[64];
    int len = 0;
    buf[len++] = 'g'; buf[len++] = 'e'; buf[len++] = 't';
    buf[len++] = '['; buf[len++] = '0' + (char)index; buf[len++] = ']';
    buf[len++] = '=';
    if (result < 0) { buf[len++] = '-'; result = -result; }
    if (result >= 100) buf[len++] = '0' + (char)((result / 100) % 10);
    if (result >= 10) buf[len++] = '0' + (char)((result / 10) % 10);
    buf[len++] = '0' + (char)(result % 10);
    ic0_debug_print_impl((uint32_t)(uintptr_t)buf, len);
    return (index >= 0 && index < 8) ? (int64_t)ouc_arg_i32[(int32_t)index] : 0;
}

/* Called from C to set argument for Idris2 */
void ouc_c_set_arg_i32(int32_t index, int32_t value) {
    if (index >= 0 && index < 8) {
        ouc_arg_i32[index] = value;
    }
}

/* Called from C to get result from Idris2 */
int32_t ouc_c_get_result_i32(void) {
    return ouc_result_i32;
}

/* Reset communication state */
void ouc_reset_ffi(void) {
    ouc_result_i32 = 0;
    for (int i = 0; i < 8; i++) {
        ouc_arg_i32[i] = 0;
    }
}

/* State initialization flag (persistent across calls) */
void ouc_set_state_initialized(int64_t value) {
    ouc_state_initialized = (int32_t)value;
}

int64_t ouc_get_state_initialized(void) {
    /* Debug: log the state check */
    char buf[32] = "state=";
    int len = 6;
    int32_t val = ouc_state_initialized;
    if (val < 0) { buf[len++] = '-'; val = -val; }
    buf[len++] = '0' + (char)(val % 10);
    ic0_debug_print_impl((uint32_t)(uintptr_t)buf, len);
    return (int64_t)ouc_state_initialized;
}

/* Auditor count (persistent across calls) */
void ouc_set_auditor_count(int64_t value) {
    ouc_auditor_count = (int32_t)value;
}

int64_t ouc_get_auditor_count(void) {
    /* Debug: log the count being read */
    char buf[32] = "audcnt=";
    int len = 7;
    int32_t val = ouc_auditor_count;
    if (val < 0) { buf[len++] = '-'; val = -val; }
    if (val >= 10) buf[len++] = '0' + (char)((val / 10) % 10);
    buf[len++] = '0' + (char)(val % 10);
    ic0_debug_print_impl((uint32_t)(uintptr_t)buf, len);
    return (int64_t)ouc_auditor_count;
}

int64_t ouc_inc_auditor_count(void) {
    ouc_auditor_count++;
    /* Debug: log the increment */
    char buf[32] = "inc->audcnt=";
    int len = 12;
    int32_t val = ouc_auditor_count;
    if (val < 0) { buf[len++] = '-'; val = -val; }
    if (val >= 10) buf[len++] = '0' + (char)((val / 10) % 10);
    buf[len++] = '0' + (char)(val % 10);
    ic0_debug_print_impl((uint32_t)(uintptr_t)buf, len);
    return (int64_t)ouc_auditor_count;  /* Return new count to prevent optimization */
}
