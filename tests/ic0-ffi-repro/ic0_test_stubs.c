/*
 * IC0 FFI Bug #3 Test Stubs
 *
 * This provides the C bridge between Idris2 and IC0 System API.
 * Designed to reproduce Bug #3 in the ICP environment.
 */
#include <stdint.h>

/* =============================================================================
 * WASM Imports from IC Runtime
 * ============================================================================= */

extern uint64_t ic0_time_impl(void)
    __attribute__((import_module("ic0"), import_name("time")));

extern void ic0_debug_print_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("debug_print")));

extern void ic0_msg_reply_impl(void)
    __attribute__((import_module("ic0"), import_name("msg_reply")));

extern void ic0_msg_reply_data_append_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("msg_reply_data_append")));

/* Forward declarations for debug functions */
void test_debug_str(const char* msg);
void test_debug_int(int64_t value);

/* =============================================================================
 * IC0 Stubs for Idris2 FFI
 * These match %foreign "C:ic0_*,libic0" declarations
 * ============================================================================= */

/* Return type: Idris2 Int = int64_t */
int64_t ic0_time(void) {
    test_debug_str("ic0_time called");
    uint64_t result = ic0_time_impl();
    /* Debug: log that ic0_time was called and what it returns */
    test_debug_int((int64_t)result);
    return (int64_t)result;
}

void ic0_debug_print(int64_t src, int64_t size) {
    ic0_debug_print_impl((uint32_t)src, (uint32_t)size);
}

void ic0_msg_reply(void) {
    ic0_msg_reply_impl();
}

void ic0_msg_reply_data_append(int64_t src, int64_t size) {
    ic0_msg_reply_data_append_impl((uint32_t)src, (uint32_t)size);
}

/* =============================================================================
 * Test FFI Functions
 * These provide both direct and workaround patterns
 * ============================================================================= */

/* Global for set/get workaround pattern */
static int64_t test_result = 0;

/* Direct IC0 call from C (bypasses Idris2 FFI for return value) */
int64_t test_get_time_direct(void) {
    return (int64_t)ic0_time_impl();
}

/* Set/Get pattern (OUC workaround) */
void test_set_result(int64_t value) {
    test_result = value;
}

int64_t test_get_result(void) {
    return test_result;
}

/* Debug string to replica log */
void test_debug_str(const char* msg) {
    int len = 0;
    while (msg[len]) len++;
    ic0_debug_print_impl((uint32_t)(uintptr_t)msg, len);
}

/* Debug integer to replica log */
void test_debug_int(int64_t value) {
    /* Format: "val=NNNN" */
    char buf[32] = "val=";
    int len = 4;
    int64_t v = value;

    if (v < 0) {
        buf[len++] = '-';
        v = -v;
    }

    /* Convert to string (simple, max ~20 digits for int64) */
    char digits[24];
    int dlen = 0;

    if (v == 0) {
        digits[dlen++] = '0';
    } else {
        while (v > 0) {
            digits[dlen++] = '0' + (char)(v % 10);
            v /= 10;
        }
    }

    /* Reverse into buf */
    for (int i = dlen - 1; i >= 0; i--) {
        buf[len++] = digits[i];
    }

    ic0_debug_print_impl((uint32_t)(uintptr_t)buf, len);
}

/* =============================================================================
 * Canister Entry Points
 * ============================================================================= */

/* Forward declaration of Idris2 runtime functions */
typedef void* Value;
extern Value __mainExpression_0(void);
extern Value idris2_trampoline(Value v);

/* Query: test_ffi
 * Runs the FFI test and returns results
 */
__attribute__((export_name("canister_query test_ffi")))
void canister_query_test_ffi(void) {
    test_debug_str("test_ffi: calling Idris2 main");
    /* Call Idris2 main which returns a closure - must trampoline to execute IO! */
    Value io_result = __mainExpression_0();
    (void)idris2_trampoline(io_result);  /* Execute the IO action */
    test_debug_str("test_ffi: Idris2 main returned");

    /* Get result from Idris2 (via workaround) */
    int64_t time_result = test_get_result();

    /* Reply with result as Candid nat */
    /* Simple Candid encoding: DIDL\x00\x01\x7d + nat LEB128 */
    uint8_t reply[16] = {'D', 'I', 'D', 'L', 0x00, 0x01, 0x7d};
    int idx = 7;

    /* LEB128 encode result */
    uint64_t val = (uint64_t)time_result;
    do {
        uint8_t byte = val & 0x7f;
        val >>= 7;
        if (val != 0) byte |= 0x80;
        reply[idx++] = byte;
    } while (val != 0);

    ic0_msg_reply_data_append_impl((uint32_t)(uintptr_t)reply, idx);
    ic0_msg_reply_impl();
}

/* Query: test_direct
 * Calls ic0_time directly from C (bypasses Idris2 completely)
 * If this returns non-zero, Idris2 FFI is the problem
 */
__attribute__((export_name("canister_query test_direct")))
void canister_query_test_direct(void) {
    /* Call ic0_time directly from C */
    uint64_t time = ic0_time_impl();

    /* Reply with time as Candid nat */
    uint8_t reply[16] = {'D', 'I', 'D', 'L', 0x00, 0x01, 0x7d};
    int idx = 7;

    uint64_t val = time;
    do {
        uint8_t byte = val & 0x7f;
        val >>= 7;
        if (val != 0) byte |= 0x80;
        reply[idx++] = byte;
    } while (val != 0);

    ic0_msg_reply_data_append_impl((uint32_t)(uintptr_t)reply, idx);
    ic0_msg_reply_impl();
}

/* Query: test_c_wrapper
 * Calls ic0_time via C wrapper (tests if C wrapper works)
 */
__attribute__((export_name("canister_query test_c_wrapper")))
void canister_query_test_c_wrapper(void) {
    /* Call ic0_time via C wrapper (same as what Idris2 FFI does) */
    int64_t time = ic0_time();  /* This is the C wrapper function */

    /* Reply with time as Candid nat */
    uint8_t reply[16] = {'D', 'I', 'D', 'L', 0x00, 0x01, 0x7d};
    int idx = 7;

    uint64_t val = (uint64_t)time;
    do {
        uint8_t byte = val & 0x7f;
        val >>= 7;
        if (val != 0) byte |= 0x80;
        reply[idx++] = byte;
    } while (val != 0);

    ic0_msg_reply_data_append_impl((uint32_t)(uintptr_t)reply, idx);
    ic0_msg_reply_impl();
}

/* Init */
__attribute__((export_name("canister_init")))
void canister_init(void) {
    /* Log initialization */
    const char* msg = "IC0Test init";
    ic0_debug_print_impl((uint32_t)(uintptr_t)msg, 12);
}
