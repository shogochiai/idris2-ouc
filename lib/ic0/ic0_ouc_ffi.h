/*
 * OUC FFI Bridge Header
 * Forward declarations for functions called by Idris2 generated code
 */
#ifndef IC0_OUC_FFI_H
#define IC0_OUC_FFI_H

#include <stdint.h>

/* Called from Idris2 via %foreign to set result */
void ouc_set_result_i32(int64_t value);

/* Called from Idris2 via %foreign to get argument */
int64_t ouc_get_arg_i32(int64_t index);

/* C-backed state management (persistent across WASM calls) */
void ouc_set_state_initialized(int64_t value);
int64_t ouc_get_state_initialized(void);
int64_t ouc_get_auditor_count(void);
int64_t ouc_inc_auditor_count(void);

/* Called from C to set argument for Idris2 */
void ouc_c_set_arg_i32(int32_t index, int32_t value);

/* Called from C to get result from Idris2 */
int32_t ouc_c_get_result_i32(void);

/* Reset communication state */
void ouc_reset_ffi(void);

/* Candid buffer (Idris2 writes encoded Candid for C to read) */
void ouc_candid_write_byte(int64_t index, int64_t byte);
void ouc_candid_set_len(int64_t len);
void ouc_candid_clear(void);

/* JSON buffer (C sets JSON for Idris2 to read) */
int64_t ouc_json_get_len(void);
int64_t ouc_json_get_byte(int64_t index);

#endif /* IC0_OUC_FFI_H */
