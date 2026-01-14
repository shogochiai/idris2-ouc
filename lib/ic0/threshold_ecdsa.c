/*
 * Threshold ECDSA Implementation for OUC
 *
 * Provides t-ECDSA signing via ICP Management Canister.
 * Used for signing EVM transactions without single-key custody.
 */
#include <stdint.h>
#include <string.h>

/* IC0 imports */
extern void ic0_call_new(int32_t callee_src, int32_t callee_size,
                         int32_t name_src, int32_t name_size,
                         int32_t reply_fun, int32_t reply_env,
                         int32_t reject_fun, int32_t reject_env);
extern void ic0_call_data_append(int32_t src, int32_t size);
extern void ic0_call_cycles_add128(uint64_t high, uint64_t low);
extern int32_t ic0_call_perform(void);
extern void ic0_debug_print(int32_t src, int32_t size);

/* =============================================================================
 * Storage for t-ECDSA operations
 * ============================================================================= */

/* Management canister ID: aaaaa-aa (empty principal) */
static const uint8_t MANAGEMENT_CANISTER[] = {};
static const int32_t MANAGEMENT_CANISTER_SIZE = 0;

/* Method names */
static const char METHOD_SIGN[] = "sign_with_ecdsa";
static const char METHOD_PUBKEY[] = "ecdsa_public_key";

/* Key names */
static const char KEY_PRODUCTION[] = "key_1";
static const char KEY_TEST[] = "test_key_1";
static const char KEY_LOCAL[] = "dfx_test_key";

/* Storage for signing request */
static uint8_t g_message_hash[32];
static uint8_t g_derivation_path[128];
static uint32_t g_derivation_path_len = 0;
static uint8_t g_key_name[32];
static uint32_t g_key_name_len = 0;

/* Storage for signature result */
static uint8_t g_signature[72];  /* DER encoded max size */
static uint32_t g_signature_len = 0;
static int32_t g_sign_status = 0;  /* 0=pending, 1=success, -1=error */

/* Storage for public key */
static uint8_t g_public_key[65];  /* SEC1 uncompressed */
static uint32_t g_public_key_len = 0;
static uint8_t g_chain_code[32];

/* =============================================================================
 * LEB128 Encoding
 * ============================================================================= */

static uint32_t encode_leb128_unsigned(uint8_t* buf, uint64_t value) {
    uint32_t len = 0;
    do {
        uint8_t byte = value & 0x7F;
        value >>= 7;
        if (value != 0) byte |= 0x80;
        buf[len++] = byte;
    } while (value != 0);
    return len;
}

static uint32_t encode_leb128_signed(uint8_t* buf, int64_t value) {
    uint32_t len = 0;
    int more = 1;
    while (more) {
        uint8_t byte = value & 0x7F;
        value >>= 7;
        if ((value == 0 && (byte & 0x40) == 0) ||
            (value == -1 && (byte & 0x40) != 0)) {
            more = 0;
        } else {
            byte |= 0x80;
        }
        buf[len++] = byte;
    }
    return len;
}

/* =============================================================================
 * Candid Encoding for sign_with_ecdsa
 * ============================================================================= */

/*
 * sign_with_ecdsa request:
 * record {
 *   message_hash : blob;        // 32 bytes
 *   derivation_path : vec blob; // list of byte arrays
 *   key_id : record {
 *     curve : variant { secp256k1 };
 *     name : text;
 *   };
 * }
 */
static uint32_t encode_sign_request(uint8_t* buf) {
    uint32_t pos = 0;

    /* DIDL magic */
    buf[pos++] = 'D';
    buf[pos++] = 'I';
    buf[pos++] = 'D';
    buf[pos++] = 'L';

    /* Type table: 4 types
     * Type 0: vec blob (derivation_path)
     * Type 1: record { curve: variant; name: text } (key_id)
     * Type 2: variant { secp256k1 } (curve)
     * Type 3: record { message_hash: blob; derivation_path: vec blob; key_id: record } (main)
     */
    pos += encode_leb128_unsigned(buf + pos, 4);  /* 4 types */

    /* Type 0: vec blob = 0x6D 0x68 (vec of blob) */
    buf[pos++] = 0x6D;  /* vec */
    pos += encode_leb128_signed(buf + pos, -19);  /* blob = -19 */

    /* Type 1: record { curve: Type2; name: text } */
    buf[pos++] = 0x6C;  /* record */
    pos += encode_leb128_unsigned(buf + pos, 2);  /* 2 fields */
    /* field hash for "curve" = 0x8DF6D6D2 */
    pos += encode_leb128_unsigned(buf + pos, 0x8DF6D6D2UL & 0xFFFFFFFF);
    pos += encode_leb128_unsigned(buf + pos, 2);  /* type 2 */
    /* field hash for "name" = 0xD3C5CC99 */
    pos += encode_leb128_unsigned(buf + pos, 0xD3C5CC99UL & 0xFFFFFFFF);
    pos += encode_leb128_signed(buf + pos, -15);  /* text = -15 */

    /* Type 2: variant { secp256k1 } */
    buf[pos++] = 0x6B;  /* variant */
    pos += encode_leb128_unsigned(buf + pos, 1);  /* 1 variant */
    /* field hash for "secp256k1" = 0xCFD1E33B */
    pos += encode_leb128_unsigned(buf + pos, 0xCFD1E33BUL & 0xFFFFFFFF);
    pos += encode_leb128_signed(buf + pos, -17);  /* null = -17 */

    /* Type 3: record { derivation_path: Type0; key_id: Type1; message_hash: blob } */
    buf[pos++] = 0x6C;  /* record */
    pos += encode_leb128_unsigned(buf + pos, 3);  /* 3 fields */
    /* Candid field hashes in ascending order:
     * derivation_path = 0x8F3AB8BA
     * key_id = 0x931C2F2A
     * message_hash = 0xCE890A2B
     */
    pos += encode_leb128_unsigned(buf + pos, 0x8F3AB8BAUL & 0xFFFFFFFF);
    pos += encode_leb128_unsigned(buf + pos, 0);  /* type 0 */
    pos += encode_leb128_unsigned(buf + pos, 0x931C2F2AUL & 0xFFFFFFFF);
    pos += encode_leb128_unsigned(buf + pos, 1);  /* type 1 */
    pos += encode_leb128_unsigned(buf + pos, 0xCE890A2BUL & 0xFFFFFFFF);
    pos += encode_leb128_signed(buf + pos, -19);  /* blob = -19 */

    /* Argument count: 1 */
    pos += encode_leb128_unsigned(buf + pos, 1);

    /* Argument type: Type 3 */
    pos += encode_leb128_unsigned(buf + pos, 3);

    /* Now encode values in field order (sorted by hash) */

    /* derivation_path: vec blob */
    /* For now, empty path */
    uint32_t path_count = g_derivation_path_len / 4;  /* Assuming 4-byte segments */
    pos += encode_leb128_unsigned(buf + pos, path_count);
    for (uint32_t i = 0; i < path_count; i++) {
        pos += encode_leb128_unsigned(buf + pos, 4);  /* 4 bytes per segment */
        memcpy(buf + pos, g_derivation_path + i * 4, 4);
        pos += 4;
    }

    /* key_id: record { curve, name } */
    /* curve: variant index 0 (secp256k1), null value */
    pos += encode_leb128_unsigned(buf + pos, 0);  /* variant index */
    /* name: text */
    pos += encode_leb128_unsigned(buf + pos, g_key_name_len);
    memcpy(buf + pos, g_key_name, g_key_name_len);
    pos += g_key_name_len;

    /* message_hash: blob (32 bytes) */
    pos += encode_leb128_unsigned(buf + pos, 32);
    memcpy(buf + pos, g_message_hash, 32);
    pos += 32;

    return pos;
}

/* =============================================================================
 * Callback functions for async calls
 * ============================================================================= */

/* Reply callback for sign_with_ecdsa */
void ecdsa_sign_reply_callback(void) {
    /* TODO: Parse reply and extract signature */
    g_sign_status = 1;

    char msg[] = "t-ECDSA sign reply received";
    ic0_debug_print((int32_t)(uintptr_t)msg, sizeof(msg) - 1);
}

/* Reject callback for sign_with_ecdsa */
void ecdsa_sign_reject_callback(void) {
    g_sign_status = -1;

    char msg[] = "t-ECDSA sign rejected";
    ic0_debug_print((int32_t)(uintptr_t)msg, sizeof(msg) - 1);
}

/* =============================================================================
 * FFI Functions for Idris2
 * ============================================================================= */

/* Set message hash (8 x uint32 = 32 bytes) */
void ouc_ecdsa_set_message_hash(
    uint32_t h0, uint32_t h1, uint32_t h2, uint32_t h3,
    uint32_t h4, uint32_t h5, uint32_t h6, uint32_t h7
) {
    uint32_t* hash32 = (uint32_t*)g_message_hash;
    hash32[0] = h0; hash32[1] = h1; hash32[2] = h2; hash32[3] = h3;
    hash32[4] = h4; hash32[5] = h5; hash32[6] = h6; hash32[7] = h7;
}

/* Set key name: 0=production, 1=test, 2=local */
void ouc_ecdsa_set_key(int64_t key_type) {
    const char* name;
    uint32_t len;

    switch ((int32_t)key_type) {
        case 0:
            name = KEY_PRODUCTION;
            len = sizeof(KEY_PRODUCTION) - 1;
            break;
        case 1:
            name = KEY_TEST;
            len = sizeof(KEY_TEST) - 1;
            break;
        case 2:
        default:
            name = KEY_LOCAL;
            len = sizeof(KEY_LOCAL) - 1;
            break;
    }

    memcpy(g_key_name, name, len);
    g_key_name_len = len;
}

/* Set derivation path segment (up to 5 segments, 4 bytes each) */
void ouc_ecdsa_set_derivation_segment(int64_t index, uint32_t value) {
    if (index >= 0 && index < 5) {
        uint32_t* path32 = (uint32_t*)g_derivation_path;
        path32[(int32_t)index] = value;
        if (((int32_t)index + 1) * 4 > (int32_t)g_derivation_path_len) {
            g_derivation_path_len = ((int32_t)index + 1) * 4;
        }
    }
}

/* Clear derivation path */
void ouc_ecdsa_clear_path(void) {
    g_derivation_path_len = 0;
    memset(g_derivation_path, 0, sizeof(g_derivation_path));
}

/* Initiate sign_with_ecdsa call */
int32_t ouc_ecdsa_sign(void) {
    /* Reset status */
    g_sign_status = 0;
    g_signature_len = 0;

    /* Encode request */
    uint8_t request[512];
    uint32_t request_len = encode_sign_request(request);

    char msg[64] = "t-ECDSA sign request len=";
    int len = 25;
    if (request_len >= 100) msg[len++] = '0' + (char)((request_len / 100) % 10);
    if (request_len >= 10) msg[len++] = '0' + (char)((request_len / 10) % 10);
    msg[len++] = '0' + (char)(request_len % 10);
    ic0_debug_print((int32_t)(uintptr_t)msg, len);

    /* Create inter-canister call */
    ic0_call_new(
        (int32_t)(uintptr_t)MANAGEMENT_CANISTER, MANAGEMENT_CANISTER_SIZE,
        (int32_t)(uintptr_t)METHOD_SIGN, sizeof(METHOD_SIGN) - 1,
        0, 0,  /* reply callback (table index TBD) */
        0, 0   /* reject callback */
    );

    /* Append request data */
    ic0_call_data_append((int32_t)(uintptr_t)request, request_len);

    /* Attach cycles: 25B for production, 10B for test */
    uint64_t cycles = 25000000000ULL;  /* 25B cycles */
    ic0_call_cycles_add128(0, cycles);

    /* Perform async call */
    int32_t result = ic0_call_perform();

    if (result == 0) {
        char ok[] = "t-ECDSA call initiated";
        ic0_debug_print((int32_t)(uintptr_t)ok, sizeof(ok) - 1);
    } else {
        char err[] = "t-ECDSA call failed";
        ic0_debug_print((int32_t)(uintptr_t)err, sizeof(err) - 1);
    }

    return result;
}

/* Get signature status: 0=pending, 1=success, -1=error */
int64_t ouc_ecdsa_get_status(void) {
    return (int64_t)g_sign_status;
}

/* Get signature length */
int64_t ouc_ecdsa_get_signature_len(void) {
    return (int64_t)g_signature_len;
}

/* Copy signature byte at index */
int64_t ouc_ecdsa_get_signature_byte(int64_t index) {
    if (index >= 0 && index < (int64_t)g_signature_len) {
        return (int64_t)g_signature[(int32_t)index];
    }
    return 0;
}

/* Get public key length */
int64_t ouc_ecdsa_get_pubkey_len(void) {
    return (int64_t)g_public_key_len;
}

/* Copy public key byte at index */
int64_t ouc_ecdsa_get_pubkey_byte(int64_t index) {
    if (index >= 0 && index < (int64_t)g_public_key_len) {
        return (int64_t)g_public_key[(int32_t)index];
    }
    return 0;
}
