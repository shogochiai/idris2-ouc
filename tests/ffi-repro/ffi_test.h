/*
 * FFI Test Header - Forward Declarations
 * Included via -include to fix implicit function declaration errors
 */
#ifndef FFI_TEST_H
#define FFI_TEST_H

#include <stdint.h>

/* FFI functions from ffi_test.c */
int64_t ffi_return_42(void);
int64_t ffi_add_one(int64_t x);
void ffi_set_result(int64_t value);
int64_t ffi_get_result(void);
void ffi_set_arg(int64_t value);
int64_t ffi_get_arg(void);
int64_t ffi_roundtrip(int64_t x);
void ffi_debug_int(const char* msg, int64_t value);

#endif /* FFI_TEST_H */
