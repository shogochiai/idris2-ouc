/*
 * FFI Bug #3 Minimal Reproduction Case
 *
 * This C file provides simple FFI functions to test Idris2 RefC FFI
 * round-trip behavior when compiled to WASM.
 *
 * Expected: Idris2 calls C function, gets return value, uses it correctly.
 * Bug #3: Idris2 receives 0 instead of the actual return value.
 */
#include <stdint.h>
#include <stdio.h>

/* Global storage for FFI communication */
static int64_t ffi_result = 0;
static int64_t ffi_arg = 0;

/* Test function 1: Return a constant value */
int64_t ffi_return_42(void) {
    return 42;
}

/* Test function 2: Return the argument + 1 */
int64_t ffi_add_one(int64_t x) {
    return x + 1;
}

/* Test function 3: Set result and return it (like OUC pattern) */
void ffi_set_result(int64_t value) {
    ffi_result = value;
}

int64_t ffi_get_result(void) {
    return ffi_result;
}

/* Test function 4: Set arg, process, get result */
void ffi_set_arg(int64_t value) {
    ffi_arg = value;
}

int64_t ffi_get_arg(void) {
    return ffi_arg;
}

/* Test function 5: Round-trip test - set arg, return arg+10 */
int64_t ffi_roundtrip(int64_t x) {
    ffi_arg = x;
    ffi_result = x + 10;
    return ffi_result;
}

/* Debug print for WASM (stub - will be replaced by IC0 debug_print) */
void ffi_debug_print(const char* msg, int64_t value) {
#ifndef __wasm__
    printf("%s: %lld\n", msg, (long long)value);
#endif
}

/* Debug print for Idris2 FFI - takes String and Int */
void ffi_debug_int(const char* msg, int64_t value) {
    printf("%s: %lld\n", msg, (long long)value);
}
