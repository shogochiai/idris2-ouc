/*
 * OUC Canister Entry Points
 *
 * Bridges IC canister interface with Idris2 RefC generated code.
 * Each canister_query/canister_update method dispatches to Idris2 functions.
 *
 * For now, this is a minimal viable canister (MVC) that returns placeholder
 * responses until Candid encoding is implemented.
 */
#include <stdint.h>
#include <string.h>

/* IC0 imports */
extern void ic0_msg_reply(void);
extern void ic0_msg_reply_data_append(int32_t src, int32_t size);
extern int32_t ic0_msg_arg_data_size(void);
extern void ic0_msg_arg_data_copy(int32_t dst, int32_t offset, int32_t size);
extern int32_t ic0_msg_caller_size(void);
extern void ic0_msg_caller_copy(int32_t dst, int32_t offset, int32_t size);
extern int32_t ic0_msg_reject_code(void);
extern int32_t ic0_msg_reject_msg_size(void);
extern void ic0_msg_reject_msg_copy(int32_t dst, int32_t offset, int32_t size);
extern uint64_t ic0_time(void);
extern void ic0_debug_print(int32_t src, int32_t size);
extern void ic0_trap(int32_t src, int32_t size);
extern int32_t ic0_canister_self_size(void);
extern void ic0_canister_self_copy(int32_t dst, int32_t offset, int32_t size);

/* Stable memory (for ic-wasm profiling support) */
extern int64_t ic0_stable64_grow(int64_t new_pages);

/* Inter-canister calls (for HTTP Outcall) */
extern void ic0_call_new(int32_t callee_src, int32_t callee_size,
                         int32_t name_src, int32_t name_size,
                         int32_t reply_fun, int32_t reply_env,
                         int32_t reject_fun, int32_t reject_env);
extern void ic0_call_data_append(int32_t src, int32_t size);
extern void ic0_call_cycles_add128(uint64_t high, uint64_t low);
extern int32_t ic0_call_perform(void);

/* Forward declarations from Idris2 generated code */
extern void* __mainExpression_0(void);  /* Idris2 main entry - returns IO closure */
extern void* idris2_trampoline(void*);  /* Execute Idris2 closure (from RefC runtime) */

/* Forward declarations from ic0_stubs.c (FFI bridge) */
extern void ouc_c_set_arg_i32(int32_t index, int32_t value);
extern int32_t ouc_c_get_result_i32(void);
extern void ouc_reset_ffi(void);
extern int64_t ouc_get_auditor_count(void);  /* Direct access for debugging */
extern int64_t ouc_get_proposal_count(void);  /* C-backed proposal count */

/* Forward declarations from sqlite_stable.c (SQLite persistence) */
extern int sqlite_stable_save(uint32_t schema_version, uint64_t timestamp);
extern int sqlite_stable_load(uint32_t* out_schema_version);
extern int sqlite_stable_has_snapshot(void);
extern int64_t ouc_inc_proposal_count(void);  /* Increment and return new ID */

/* A-Life Economics: Protocol Account functions */
extern uint64_t ouc_accept_and_donate(const char* protocol_id);
extern uint64_t ouc_get_protocol_balance(const char* protocol_id);
extern uint8_t ouc_get_protocol_tier(const char* protocol_id);
extern uint32_t ouc_get_protocol_count(void);

/* Candid buffer FFI (for Idris2 Candid encoding) */
extern void ouc_c_set_json(const char* json);
extern uint8_t* ouc_c_get_candid_buf(void);
extern int32_t ouc_c_get_candid_len(void);

/* Command constants (must match Main.idr) */
/* Query commands (0-9) */
#define CMD_INIT               0
#define CMD_GET_VERSION        1
#define CMD_GET_PROPOSAL_COUNT 2
#define CMD_GET_AUDITOR_COUNT  3
#define CMD_GET_PROPOSAL       4
/* Update commands (10+) */
#define CMD_REGISTER_AUDITOR   10
#define CMD_SUSPEND_AUDITOR    11
#define CMD_REACTIVATE_AUDITOR 12
#define CMD_SUBMIT_PROPOSAL    13
/* Candid encoding commands (100+) */
#define CMD_ENCODE_EVM_RPC     100
/* Indexer commands (30+) - must match Main.idr */
#define CMD_GET_OUC_EVENTS       30
#define CMD_GET_PROPOSAL_EVENTS  31
#define CMD_GET_DASHBOARD_SUMMARY 32
#define CMD_STORE_TEST_EVENT     33

/* Call Idris2 with a command and return the result */
static int32_t call_idris2(int32_t cmd) {
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, cmd);
    /* __mainExpression_0 returns an IO closure, idris2_trampoline executes it */
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);
    return ouc_c_get_result_i32();
}

/* Call Idris2 with command and one argument */
static int32_t call_idris2_with_arg(int32_t cmd, int32_t arg1) {
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, cmd);
    ouc_c_set_arg_i32(1, arg1);
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);
    return ouc_c_get_result_i32();
}

/* Alias for clarity */
#define call_idris2_1arg call_idris2_with_arg

/* Call Idris2 with command and two arguments */
static int32_t call_idris2_2arg(int32_t cmd, int32_t arg1, int32_t arg2) {
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, cmd);
    ouc_c_set_arg_i32(1, arg1);
    ouc_c_set_arg_i32(2, arg2);
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);
    return ouc_c_get_result_i32();
}

/* =============================================================================
 * Idris2 Candid Encoding (replaces build_evm_rpc_request_multichain)
 *
 * Uses Idris2's type-safe Candid encoder via FFI:
 * 1. C sets JSON in ouc_json_buf via ouc_c_set_json()
 * 2. C sets chain_id and max_bytes in args
 * 3. C calls Idris2 with CMD_ENCODE_EVM_RPC
 * 4. Idris2 encodes Candid to ouc_candid_buf
 * 5. C reads result from ouc_c_get_candid_buf/len
 * ============================================================================= */

/* Encode EVM RPC request using Idris2 (type-safe, hash/index derived from ADT)
 * json_rpc: JSON-RPC request string
 * chain_id: 1=EthMainnet, 11155111=Sepolia, 8453=Base, 42161=Arbitrum
 * max_bytes: maximum response size
 * Returns: length of encoded Candid, or -1 on error
 */
static int32_t encode_evm_rpc_idris2(const char* json_rpc, int32_t chain_id, int32_t max_bytes) {
    /* Set JSON in shared buffer */
    ouc_c_set_json(json_rpc);

    /* Call Idris2 encoder */
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, CMD_ENCODE_EVM_RPC);
    ouc_c_set_arg_i32(1, chain_id);
    ouc_c_set_arg_i32(2, max_bytes);
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);

    return ouc_c_get_result_i32();
}

/* =============================================================================
 * Candid Argument Parsing
 * ============================================================================= */

/* Argument buffer for Candid parsing */
static uint8_t arg_buf[1024];
static int32_t arg_buf_size = 0;

/* Load Candid arguments into buffer */
static void load_candid_args(void) {
    arg_buf_size = ic0_msg_arg_data_size();
    if (arg_buf_size > (int32_t)sizeof(arg_buf)) {
        arg_buf_size = sizeof(arg_buf);
    }
    if (arg_buf_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)arg_buf, 0, arg_buf_size);
    }
}

/* Parse LEB128 unsigned integer from buffer at offset, return value and new offset */
static uint64_t parse_leb128(int32_t offset, int32_t* new_offset) {
    uint64_t result = 0;
    int shift = 0;
    while (offset < arg_buf_size) {
        uint8_t byte = arg_buf[offset++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    *new_offset = offset;
    return result;
}

/* Parse Candid nat argument (DIDL + type table + nat value)
 * Returns: parsed nat value, or 0 on error
 * Candid format: "DIDL" + type_count(leb128) + arg_count(leb128) + type_codes + values
 */
static uint64_t parse_candid_nat_arg(void) {
    load_candid_args();

    /* Check DIDL magic (0x4449444C) */
    if (arg_buf_size < 7) return 0;
    if (arg_buf[0] != 'D' || arg_buf[1] != 'I' || arg_buf[2] != 'D' || arg_buf[3] != 'L') {
        return 0;
    }

    int32_t offset = 4;
    int32_t new_offset;

    /* Parse type table count (should be 0 for simple nat) */
    uint64_t type_count = parse_leb128(offset, &new_offset);
    offset = new_offset;

    /* Skip type table entries (compound types) */
    for (uint64_t i = 0; i < type_count; i++) {
        /* Skip type definition - simplified, assume small types */
        parse_leb128(offset, &new_offset);
        offset = new_offset;
    }

    /* Parse arg count (should be 1) */
    uint64_t arg_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    if (arg_count < 1) return 0;

    /* Parse type code for first arg (0x7D = nat, 0x7C = int) */
    int32_t type_code_offset = offset;
    /* Candid type codes are signed LEB128, but nat is 0x7D (-3 signed) */
    uint8_t type_byte = arg_buf[offset++];
    /* For nat (0x7D = 125), it's a single byte */

    /* Parse the nat value */
    uint64_t value = parse_leb128(offset, &new_offset);
    return value;
}

/* Text argument buffer (for parsed text) */
static char text_arg_buf[512];
static int32_t text_arg_len = 0;

/* Parse Candid text argument
 * Returns: length of parsed text (stored in text_arg_buf), or 0 on error
 * Candid format: "DIDL" + type_count + arg_count + type_code + len(leb128) + bytes
 */
static int32_t parse_candid_text_arg(void) {
    load_candid_args();
    text_arg_len = 0;

    /* Check DIDL magic */
    if (arg_buf_size < 7) return 0;
    if (arg_buf[0] != 'D' || arg_buf[1] != 'I' || arg_buf[2] != 'D' || arg_buf[3] != 'L') {
        return 0;
    }

    int32_t offset = 4;
    int32_t new_offset;

    /* Parse type table count (should be 0 for simple text) */
    uint64_t type_count = parse_leb128(offset, &new_offset);
    offset = new_offset;

    /* Skip type table entries */
    for (uint64_t i = 0; i < type_count; i++) {
        parse_leb128(offset, &new_offset);
        offset = new_offset;
    }

    /* Parse arg count (should be 1) */
    uint64_t arg_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    if (arg_count < 1) return 0;

    /* Parse type code (0x71 = text) */
    uint8_t type_byte = arg_buf[offset++];
    /* 0x71 = 113 unsigned, or -15 signed = text type */

    /* Parse text length */
    uint64_t text_len = parse_leb128(offset, &new_offset);
    offset = new_offset;

    /* Copy text to buffer */
    if (text_len >= sizeof(text_arg_buf)) {
        text_len = sizeof(text_arg_buf) - 1;
    }
    for (uint64_t i = 0; i < text_len && offset < arg_buf_size; i++) {
        text_arg_buf[i] = (char)arg_buf[offset++];
    }
    text_arg_buf[text_len] = '\0';
    text_arg_len = (int32_t)text_len;

    return text_arg_len;
}

/* =============================================================================
 * Helper Functions
 * ============================================================================= */

static void debug(const char* msg) {
    ic0_debug_print((int32_t)(uintptr_t)msg, (int32_t)strlen(msg));
}

static void reply_text(const char* msg) {
    ic0_msg_reply_data_append((int32_t)(uintptr_t)msg, (int32_t)strlen(msg));
    ic0_msg_reply();
}

static void trap_with(const char* msg) {
    ic0_trap((int32_t)(uintptr_t)msg, (int32_t)strlen(msg));
}

/* Simple Candid encoding helpers (DIDL prefix + type table + values) */
/* Candid "empty response" = DIDL\0\0 */
static const uint8_t CANDID_EMPTY[] = { 0x44, 0x49, 0x44, 0x4C, 0x00, 0x00 };

/* Candid "text" response (type 71 = text) */
/* DIDL + empty type table (0) + 1 arg + text type (0x71) + text data */
static void reply_candid_text(const char* text) {
    uint32_t len = (uint32_t)strlen(text);
    /* DIDL magic */
    uint8_t header[] = { 0x44, 0x49, 0x44, 0x4C, 0x00, 0x01, 0x71 };
    ic0_msg_reply_data_append((int32_t)(uintptr_t)header, 7);
    /* LEB128 length (proper encoding for any length) */
    uint8_t leb_buf[5];
    int32_t leb_len = 0;
    uint32_t val = len;
    do {
        uint8_t byte = (uint8_t)(val & 0x7F);
        val >>= 7;
        if (val != 0) byte |= 0x80;
        leb_buf[leb_len++] = byte;
    } while (val != 0);
    ic0_msg_reply_data_append((int32_t)(uintptr_t)leb_buf, leb_len);
    /* Text content */
    ic0_msg_reply_data_append((int32_t)(uintptr_t)text, (int32_t)len);
    ic0_msg_reply();
}

/* Candid "nat" response */
static void reply_candid_nat(uint64_t value) {
    uint8_t header[] = { 0x44, 0x49, 0x44, 0x4C, 0x00, 0x01, 0x7D }; /* 0x7D = nat */
    ic0_msg_reply_data_append((int32_t)(uintptr_t)header, 7);
    /* LEB128 encode value (simplified for small values) */
    uint8_t buf[10];
    int i = 0;
    do {
        buf[i] = (uint8_t)(value & 0x7F);
        value >>= 7;
        if (value != 0) buf[i] |= 0x80;
        i++;
    } while (value != 0);
    ic0_msg_reply_data_append((int32_t)(uintptr_t)buf, i);
    ic0_msg_reply();
}

/* Candid "null" response */
static void reply_candid_null(void) {
    uint8_t response[] = { 0x44, 0x49, 0x44, 0x4C, 0x00, 0x01, 0x7F }; /* 0x7F = null */
    ic0_msg_reply_data_append((int32_t)(uintptr_t)response, 7);
    ic0_msg_reply();
}

/* =============================================================================
 * Canister Lifecycle
 * ============================================================================= */

__attribute__((used, visibility("default"), export_name("canister_init")))
void canister_init(void) {
    debug("OUC: canister_init");

    /* Pre-allocate stable memory for ic-wasm profiling support
     * Grow 10 pages (640KB) at page 0 for profiling data
     * Must be done before first update call to avoid trap in __get_profiling */
    int64_t grow_result = ic0_stable64_grow(10);
    if (grow_result < 0) {
        debug("OUC: stable memory grow failed");
    } else {
        debug("OUC: stable memory pre-allocated for profiling");
    }

    int32_t result = call_idris2(CMD_INIT);
    if (result == 1) {
        debug("OUC: initialized successfully");
    } else {
        debug("OUC: initialization failed");
    }
}

__attribute__((used, visibility("default"), export_name("canister_pre_upgrade")))
void canister_pre_upgrade(void) {
    debug("OUC: canister_pre_upgrade");

    /* Save SQLite database to stable memory */
    uint64_t timestamp = ic0_time();
    int rc = sqlite_stable_save(1, timestamp);  /* schema_version = 1 */
    if (rc == 0) {
        debug("OUC: SQLite saved to stable memory");
    } else {
        debug("OUC: SQLite save failed");
    }
}

__attribute__((used, visibility("default"), export_name("canister_post_upgrade")))
void canister_post_upgrade(void) {
    debug("OUC: canister_post_upgrade");

    /* Try to restore SQLite from stable memory first */
    if (sqlite_stable_has_snapshot()) {
        debug("OUC: Found SQLite snapshot, restoring...");
        uint32_t schema_version = 0;
        int rc = sqlite_stable_load(&schema_version);
        if (rc == 0) {
            debug("OUC: SQLite restored from stable memory");
            /* Still call CMD_INIT to initialize Idris2 state (non-SQLite parts) */
            int32_t result = call_idris2(CMD_INIT);
            if (result == 1) {
                debug("OUC: post_upgrade state initialized");
            }
            return;
        } else {
            debug("OUC: SQLite restore failed, initializing fresh");
        }
    }

    /* No snapshot or restore failed - initialize fresh */
    int32_t result = call_idris2(CMD_INIT);
    if (result == 1) {
        debug("OUC: post_upgrade initialized state (fresh)");
    } else {
        debug("OUC: post_upgrade state init failed");
    }
}

/* =============================================================================
 * Query Methods
 * ============================================================================= */

__attribute__((used, visibility("default"), export_name("canister_query getProposal")))
void canister_query_getProposal(void) {
    debug("OUC: getProposal");

    /* Parse ProposalId (nat) from Candid arguments */
    uint64_t proposal_id = parse_candid_nat_arg();
    debug("OUC: getProposal - parsed id");

    /* Check against C-backed proposal count (persistent) */
    int64_t count = ouc_get_proposal_count();
    int found = (proposal_id < (uint64_t)count) ? 1 : 0;

    /* Return result as JSON text (MVP) */
    char response[128];
    if (found) {
        /* Proposal found - return simple JSON */
        int len = 0;
        const char* prefix = "{\"id\":";
        while (prefix[len]) { response[len] = prefix[len]; len++; }

        /* Add proposal ID */
        uint64_t id = proposal_id;
        char digits[20];
        int dlen = 0;
        if (id == 0) {
            digits[dlen++] = '0';
        } else {
            while (id > 0) {
                digits[dlen++] = '0' + (char)(id % 10);
                id /= 10;
            }
        }
        for (int i = dlen - 1; i >= 0; i--) {
            response[len++] = digits[i];
        }

        const char* suffix = ",\"status\":\"pending\"}";
        for (int i = 0; suffix[i]; i++) {
            response[len++] = suffix[i];
        }
        response[len] = '\0';
        reply_candid_text(response);
    } else {
        reply_candid_text("{\"error\":\"not_found\"}");
    }
}

__attribute__((used, visibility("default"), export_name("canister_query getProposalsByChain")))
void canister_query_getProposalsByChain(void) {
    debug("OUC: getProposalsByChain");
    reply_candid_text("getProposalsByChain: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getProposalsByStatus")))
void canister_query_getProposalsByStatus(void) {
    debug("OUC: getProposalsByStatus");
    reply_candid_text("getProposalsByStatus: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getAuditor")))
void canister_query_getAuditor(void) {
    debug("OUC: getAuditor");
    reply_candid_text("getAuditor: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getActiveAuditors")))
void canister_query_getActiveAuditors(void) {
    debug("OUC: getActiveAuditors");
    reply_candid_text("getActiveAuditors: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getReviewsForProposal")))
void canister_query_getReviewsForProposal(void) {
    debug("OUC: getReviewsForProposal");
    reply_candid_text("getReviewsForProposal: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getPendingReward")))
void canister_query_getPendingReward(void) {
    debug("OUC: getPendingReward");
    reply_candid_nat(0);
}

__attribute__((used, visibility("default"), export_name("canister_query getTotalDistributed")))
void canister_query_getTotalDistributed(void) {
    debug("OUC: getTotalDistributed");
    reply_candid_nat(0);
}

__attribute__((used, visibility("default"), export_name("canister_query getTreasuryBalance")))
void canister_query_getTreasuryBalance(void) {
    debug("OUC: getTreasuryBalance");
    reply_candid_nat(0);
}

__attribute__((used, visibility("default"), export_name("canister_query getOwner")))
void canister_query_getOwner(void) {
    debug("OUC: getOwner");
    /* TODO: Return actual owner principal */
    reply_candid_text("owner: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_query getVersion")))
void canister_query_getVersion(void) {
    debug("OUC: getVersion");
    int32_t version = call_idris2(CMD_GET_VERSION);
    reply_candid_nat((uint64_t)version);
}

__attribute__((used, visibility("default"), export_name("canister_query getProposalCount")))
void canister_query_getProposalCount(void) {
    debug("OUC: getProposalCount");
    /* Bypass Idris2 - call C-backed storage directly */
    int64_t count = ouc_get_proposal_count();
    reply_candid_nat((uint64_t)count);
}

__attribute__((used, visibility("default"), export_name("canister_query getAuditorCount")))
void canister_query_getAuditorCount(void) {
    debug("OUC: getAuditorCount");
    /* Bypass Idris2 FFI read bug - call C directly */
    int64_t count = ouc_get_auditor_count();
    reply_candid_nat((uint64_t)count);
}

/* =============================================================================
 * Update Methods
 * ============================================================================= */

__attribute__((used, visibility("default"), export_name("canister_update submitProposal")))
void canister_update_submitProposal(void) {
    debug("OUC: submitProposal");

    /* Parse rationale text from Candid */
    int32_t text_len = parse_candid_text_arg();
    if (text_len < 0) {
        reply_candid_text("error:invalid_candid");
        return;
    }

    /* Create proposal using C-backed storage (persistent) */
    int64_t new_id = ouc_inc_proposal_count();

    /* Return proposal ID as JSON */
    char buf[64];
    buf[0] = '{'; buf[1] = '"'; buf[2] = 'i'; buf[3] = 'd'; buf[4] = '"';
    buf[5] = ':';
    int len = 6;
    /* Convert new_id to string */
    if (new_id >= 100) buf[len++] = '0' + (char)((new_id / 100) % 10);
    if (new_id >= 10) buf[len++] = '0' + (char)((new_id / 10) % 10);
    buf[len++] = '0' + (char)(new_id % 10);
    buf[len++] = '}';
    buf[len] = '\0';
    reply_candid_text(buf);
}

__attribute__((used, visibility("default"), export_name("canister_update cancelProposal")))
void canister_update_cancelProposal(void) {
    debug("OUC: cancelProposal");
    reply_candid_text("cancelProposal: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update registerAuditor")))
void canister_update_registerAuditor(void) {
    debug("OUC: registerAuditor");
    int32_t result = call_idris2(CMD_REGISTER_AUDITOR);
    /* Debug: Read count directly from C (bypasses Idris2) */
    int64_t count = ouc_get_auditor_count();
    /* Create response with count for debugging */
    char buf[64] = "registered:";
    int len = 11;
    if (result == 1) {
        buf[len++] = 'o'; buf[len++] = 'k';
    } else if (result == 0) {
        buf[len++] = 'e'; buf[len++] = 'x'; buf[len++] = 'i'; buf[len++] = 's'; buf[len++] = 't'; buf[len++] = 's';
    } else {
        buf[len++] = 'e'; buf[len++] = 'r'; buf[len++] = 'r';
    }
    buf[len++] = ','; buf[len++] = 'c'; buf[len++] = 'n'; buf[len++] = 't'; buf[len++] = '=';
    if (count >= 10) buf[len++] = '0' + (char)((count / 10) % 10);
    buf[len++] = '0' + (char)(count % 10);
    buf[len] = '\0';
    reply_candid_text(buf);
}

__attribute__((used, visibility("default"), export_name("canister_update suspendAuditor")))
void canister_update_suspendAuditor(void) {
    debug("OUC: suspendAuditor");
    /* TODO: Parse auditor index from Candid args and set in arg[1] */
    ouc_c_set_arg_i32(1, 0);  /* For now, suspend index 0 */
    int32_t result = call_idris2(CMD_SUSPEND_AUDITOR);
    if (result == 1) {
        reply_candid_text("auditor suspended");
    } else if (result == 0) {
        reply_candid_text("auditor not found");
    } else {
        reply_candid_text("error: suspension failed");
    }
}

__attribute__((used, visibility("default"), export_name("canister_update reactivateAuditor")))
void canister_update_reactivateAuditor(void) {
    debug("OUC: reactivateAuditor");
    /* TODO: Parse auditor index from Candid args and set in arg[1] */
    ouc_c_set_arg_i32(1, 0);  /* For now, reactivate index 0 */
    int32_t result = call_idris2(CMD_REACTIVATE_AUDITOR);
    if (result == 1) {
        reply_candid_text("auditor reactivated");
    } else if (result == 0) {
        reply_candid_text("auditor not found");
    } else {
        reply_candid_text("error: reactivation failed");
    }
}

__attribute__((used, visibility("default"), export_name("canister_update assignAuditor")))
void canister_update_assignAuditor(void) {
    debug("OUC: assignAuditor");
    reply_candid_text("assignAuditor: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update submitReview")))
void canister_update_submitReview(void) {
    debug("OUC: submitReview");
    reply_candid_text("submitReview: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update prepareExecution")))
void canister_update_prepareExecution(void) {
    debug("OUC: prepareExecution");
    reply_candid_text("prepareExecution: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update recordExecution")))
void canister_update_recordExecution(void) {
    debug("OUC: recordExecution");
    reply_candid_text("recordExecution: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update distributeReward")))
void canister_update_distributeReward(void) {
    debug("OUC: distributeReward");
    reply_candid_text("distributeReward: not yet implemented");
}

__attribute__((used, visibility("default"), export_name("canister_update transferOwnership")))
void canister_update_transferOwnership(void) {
    debug("OUC: transferOwnership");
    reply_candid_text("transferOwnership: not yet implemented");
}

/* =============================================================================
 * HTTP Outcall Support
 * ============================================================================= */

/* Transform query method for HTTP outcalls
 * Strips varying headers to ensure consensus across replicas
 * Input: TransformArgs = record { response: HttpResponse; context: blob }
 * Output: HttpResponse = record { status: nat; headers: vec HttpHeader; body: blob }
 *
 * The input Candid contains the full HttpResponse which we simplify to just the body.
 */
__attribute__((used, visibility("default"), export_name("canister_query transform")))
void canister_query_transform(void) {
    debug("OUC: transform - stripping headers for consensus");

    /* Load Candid arguments */
    int32_t arg_size = ic0_msg_arg_data_size();
    static uint8_t arg_buf[8192];
    if (arg_size > (int32_t)sizeof(arg_buf)) arg_size = sizeof(arg_buf);
    if (arg_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)arg_buf, 0, arg_size);
    }

    /* Parse TransformArgs to extract body from HttpResponse
     * For simplicity, we'll search for the body blob in the response
     * and return a minimal HttpResponse with just status 200 and the body */

    /* Find body blob in the response - this is a simplified parser
     * Real implementation would properly parse the Candid structure */

    /* Build simplified HttpResponse:
     * - status: 200 (nat encoded as LEB128)
     * - headers: empty vec
     * - body: same as input body
     *
     * For now, just pass through the original response
     * The important thing is that this method exists for the transform reference */

    /* Return simplified response - just echo back for now
     * This is a placeholder that demonstrates the transform mechanism works */
    static uint8_t response[8192];
    int32_t offset = 0;

    /* DIDL header */
    response[offset++] = 'D'; response[offset++] = 'I';
    response[offset++] = 'D'; response[offset++] = 'L';

    /* Type table: 3 types
     * Type 0: http_header record
     * Type 1: vec type_0 (headers)
     * Type 2: HttpResponse record */
    response[offset++] = 3;

    /* Type 0: record { value: text; name: text } */
    response[offset++] = 0x6C;  /* record */
    response[offset++] = 2;     /* 2 fields */
    /* value hash 0x31B87F71 */
    response[offset++] = 0xF1; response[offset++] = 0xBF;
    response[offset++] = 0xC2; response[offset++] = 0x8D; response[offset++] = 0x03;
    response[offset++] = 0x71;  /* text */
    /* name hash 0x48FF724B */
    response[offset++] = 0xCB; response[offset++] = 0xEC;
    response[offset++] = 0xE7; response[offset++] = 0xC7; response[offset++] = 0x04;
    response[offset++] = 0x71;  /* text */

    /* Type 1: vec type_0 */
    response[offset++] = 0x6D;  /* vec */
    response[offset++] = 0;     /* type 0 */

    /* Type 2: HttpResponse record
     * Fields sorted by hash: body=0x411B7AA2, headers=0x63085246, status=0xC6FC6F67 */
    response[offset++] = 0x6C;  /* record */
    response[offset++] = 3;     /* 3 fields */
    /* body hash 0x411B7AA2 */
    response[offset++] = 0xA2; response[offset++] = 0xF5;
    response[offset++] = 0xEB; response[offset++] = 0x88; response[offset++] = 0x04;
    response[offset++] = 0x6D; response[offset++] = 0x7B;  /* vec nat8 = blob */
    /* headers hash 0x63085246 */
    response[offset++] = 0xC6; response[offset++] = 0x84;
    response[offset++] = 0xA9; response[offset++] = 0x98; response[offset++] = 0x06;
    response[offset++] = 1;  /* type 1 */
    /* status hash - need to calculate for "status" */
    /* status = 0xC6FC6F67 */
    response[offset++] = 0xE7; response[offset++] = 0xDE;
    response[offset++] = 0xBF; response[offset++] = 0xB7; response[offset++] = 0x0C;
    response[offset++] = 0x7D;  /* nat */

    /* Type sequence: 1 arg of type 2 */
    response[offset++] = 1;
    response[offset++] = 2;

    /* Values for HttpResponse: body, headers, status */
    /* body: empty blob for now (we'd parse from input in real impl) */
    response[offset++] = 0;  /* empty blob */
    /* headers: empty vec */
    response[offset++] = 0;  /* empty vec */
    /* status: 200 */
    response[offset++] = 0xC8; response[offset++] = 0x01;  /* LEB128(200) */

    ic0_msg_reply_data_append((int32_t)(uintptr_t)response, offset);
    ic0_msg_reply();
}

/* Callback state for HTTP response */
static uint8_t http_response_buf[4096];
static int32_t http_response_len = 0;

/* Parse LEB128 unsigned from buffer, return value and advance offset */
static uint64_t parse_leb128_at(const uint8_t* buf, int32_t* offset, int32_t max_len) {
    uint64_t result = 0;
    int shift = 0;
    while (*offset < max_len) {
        uint8_t byte = buf[(*offset)++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

/* Parse HttpResponse Candid and extract body */
/* HttpResponse = record { status: nat; headers: vec {...}; body: blob } */
static int32_t parse_http_response_body(const uint8_t* buf, int32_t len,
                                         uint8_t** body_out, int32_t* body_len_out,
                                         uint64_t* status_out) {
    int32_t offset = 0;

    /* Check DIDL magic */
    if (len < 4) return -1;
    if (buf[0] != 'D' || buf[1] != 'I' || buf[2] != 'D' || buf[3] != 'L') return -2;
    offset = 4;

    /* Skip type table */
    uint64_t type_count = parse_leb128_at(buf, &offset, len);
    for (uint64_t i = 0; i < type_count; i++) {
        /* Skip type definition - simplified: just skip past this type */
        int64_t type_code = (int64_t)parse_leb128_at(buf, &offset, len);
        if (type_code == -19) { /* blob */
            /* No additional data */
        } else if (type_code == -15) { /* text */
            /* No additional data */
        } else if (type_code == -5 || type_code == -6) { /* nat, int */
            /* No additional data */
        } else if ((type_code & 0xFF) == 0x6C) { /* record */
            uint64_t field_count = parse_leb128_at(buf, &offset, len);
            for (uint64_t f = 0; f < field_count; f++) {
                parse_leb128_at(buf, &offset, len); /* field hash */
                parse_leb128_at(buf, &offset, len); /* field type */
            }
        } else if ((type_code & 0xFF) == 0x6D) { /* vec */
            parse_leb128_at(buf, &offset, len); /* element type */
        } else if ((type_code & 0xFF) == 0x6E) { /* opt */
            parse_leb128_at(buf, &offset, len); /* inner type */
        }
    }

    /* Read arg count and main type index */
    uint64_t arg_count = parse_leb128_at(buf, &offset, len);
    if (arg_count < 1) return -3;
    parse_leb128_at(buf, &offset, len); /* main type index */

    /* Parse HttpResponse record values */
    /* Expected order (by field hash): body, headers, status */
    /* IC HttpResponse: { status: nat; headers: vec; body: blob } */

    /* This is a simplified parser - assumes known field order */
    /* Real implementation would need to match field hashes */

    /* Parse status (nat) */
    *status_out = parse_leb128_at(buf, &offset, len);

    /* Skip headers (vec of records) - just get count and skip */
    uint64_t headers_count = parse_leb128_at(buf, &offset, len);
    for (uint64_t h = 0; h < headers_count; h++) {
        /* Skip header name (text) */
        uint64_t name_len = parse_leb128_at(buf, &offset, len);
        offset += (int32_t)name_len;
        /* Skip header value (text) */
        uint64_t value_len = parse_leb128_at(buf, &offset, len);
        offset += (int32_t)value_len;
    }

    /* Parse body (blob) */
    uint64_t body_len = parse_leb128_at(buf, &offset, len);
    if (offset + (int32_t)body_len > len) return -4;

    *body_out = (uint8_t*)(buf + offset);
    *body_len_out = (int32_t)body_len;

    return 0;
}

/* Extract hex value from JSON-RPC response */
/* Response format: {"jsonrpc":"2.0","id":1,"result":"0x..."} */
static int32_t extract_jsonrpc_result(const uint8_t* json, int32_t len, char* result_buf, int32_t max_len) {
    /* Find "result":" in response */
    const char* pattern = "\"result\":\"";
    int32_t pattern_len = 10;

    for (int32_t i = 0; i < len - pattern_len; i++) {
        int match = 1;
        for (int32_t j = 0; j < pattern_len && match; j++) {
            if (json[i + j] != (uint8_t)pattern[j]) match = 0;
        }
        if (match) {
            /* Found pattern, extract hex value */
            int32_t start = i + pattern_len;
            int32_t result_len = 0;
            while (start + result_len < len && json[start + result_len] != '"' && result_len < max_len - 1) {
                result_buf[result_len] = (char)json[start + result_len];
                result_len++;
            }
            result_buf[result_len] = '\0';
            return result_len;
        }
    }
    return -1;
}

/* Callback handler for HTTP response (called by IC runtime)
 * env parameter is required by IC callback signature, even if unused */
__attribute__((used, visibility("default"), export_name("http_reply_callback")))
void http_reply_callback(int32_t env) {
    (void)env;  /* Unused */
    debug("OUC: http_reply_callback");

    /* Read response data from ic0.msg_arg_data_copy */
    http_response_len = ic0_msg_arg_data_size();
    if (http_response_len > (int32_t)sizeof(http_response_buf)) {
        http_response_len = sizeof(http_response_buf);
    }
    if (http_response_len > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)http_response_buf, 0, http_response_len);
    }

    /* Parse HttpResponse Candid */
    uint8_t* body = NULL;
    int32_t body_len = 0;
    uint64_t http_status = 0;

    int32_t parse_result = parse_http_response_body(http_response_buf, http_response_len,
                                                     &body, &body_len, &http_status);

    char result[512];
    int len = 0;

    if (parse_result != 0) {
        /* Candid parse failed - return error with raw data info */
        const char* prefix = "{\"error\":\"candid_parse_failed\",\"code\":";
        while (prefix[len]) { result[len] = prefix[len]; len++; }
        if (parse_result < 0) { result[len++] = '-'; parse_result = -parse_result; }
        result[len++] = '0' + (char)(parse_result % 10);
        const char* suffix = ",\"rawLen\":";
        int slen = 0;
        while (suffix[slen]) { result[len++] = suffix[slen++]; }
        int32_t rlen = http_response_len;
        if (rlen >= 1000) result[len++] = '0' + (char)((rlen / 1000) % 10);
        if (rlen >= 100) result[len++] = '0' + (char)((rlen / 100) % 10);
        if (rlen >= 10) result[len++] = '0' + (char)((rlen / 10) % 10);
        result[len++] = '0' + (char)(rlen % 10);
        result[len++] = '}';
    } else if (http_status != 200) {
        /* HTTP error status */
        const char* prefix = "{\"error\":\"http_status\",\"status\":";
        while (prefix[len]) { result[len] = prefix[len]; len++; }
        if (http_status >= 100) result[len++] = '0' + (char)((http_status / 100) % 10);
        if (http_status >= 10) result[len++] = '0' + (char)((http_status / 10) % 10);
        result[len++] = '0' + (char)(http_status % 10);
        result[len++] = '}';
    } else {
        /* Success - extract JSON-RPC result */
        char jsonrpc_result[128];
        int32_t jsonrpc_len = extract_jsonrpc_result(body, body_len, jsonrpc_result, sizeof(jsonrpc_result));

        if (jsonrpc_len < 0) {
            const char* prefix = "{\"error\":\"jsonrpc_parse_failed\",\"bodyLen\":";
            while (prefix[len]) { result[len] = prefix[len]; len++; }
            if (body_len >= 100) result[len++] = '0' + (char)((body_len / 100) % 10);
            if (body_len >= 10) result[len++] = '0' + (char)((body_len / 10) % 10);
            result[len++] = '0' + (char)(body_len % 10);
            result[len++] = '}';
        } else {
            const char* prefix = "{\"result\":\"";
            while (prefix[len]) { result[len] = prefix[len]; len++; }
            for (int32_t i = 0; i < jsonrpc_len && len < 500; i++) {
                result[len++] = jsonrpc_result[i];
            }
            result[len++] = '"';
            result[len++] = '}';
        }
    }

    result[len] = '\0';
    reply_candid_text(result);
}

/* Callback handler for HTTP rejection
 * env parameter is required by IC callback signature, even if unused */
__attribute__((used, visibility("default"), export_name("http_reject_callback")))
void http_reject_callback(int32_t env) {
    (void)env;  /* Unused */
    debug("OUC: http_reject_callback");

    /* Get rejection details */
    int32_t reject_code = ic0_msg_reject_code();
    int32_t msg_size = ic0_msg_reject_msg_size();

    /* Build error response with rejection details */
    char response[1024];
    int32_t len = 0;
    const char* prefix = "{\"error\":\"rejected\",\"code\":";
    while (prefix[len]) { response[len] = prefix[len]; len++; }

    /* Add reject code */
    if (reject_code >= 10) response[len++] = '0' + (char)((reject_code / 10) % 10);
    response[len++] = '0' + (char)(reject_code % 10);

    /* Add message size for debugging */
    const char* size_prefix = ",\"msgSize\":";
    for (int i = 0; size_prefix[i]; i++) response[len++] = size_prefix[i];
    if (msg_size >= 100) response[len++] = '0' + (char)((msg_size / 100) % 10);
    if (msg_size >= 10) response[len++] = '0' + (char)((msg_size / 10) % 10);
    response[len++] = '0' + (char)(msg_size % 10);

    /* Add message if available (truncate if too long) */
    if (msg_size > 0) {
        const char* msg_prefix = ",\"msg\":\"";
        for (int i = 0; msg_prefix[i]; i++) response[len++] = msg_prefix[i];

        /* Copy rejection message (truncate to fit) */
        int32_t copy_size = msg_size < 700 ? msg_size : 700;
        char msg_buf[800];
        ic0_msg_reject_msg_copy((int32_t)(uintptr_t)msg_buf, 0, copy_size);
        for (int32_t i = 0; i < copy_size && len < 950; i++) {
            char c = msg_buf[i];
            /* Escape special characters */
            if (c == '"' || c == '\\') {
                response[len++] = '\\';
            }
            if (c >= 32 && c < 127) {
                response[len++] = c;
            }
        }
        response[len++] = '"';
    }

    response[len++] = '}';
    response[len] = '\0';
    reply_candid_text(response);
}

/* =============================================================================
 * Candid Encoding Helpers for HTTP Outcall
 * ============================================================================= */

/* LEB128 encode unsigned integer, return bytes written */
static int32_t encode_leb128_unsigned(uint8_t* buf, uint64_t value) {
    int32_t len = 0;
    do {
        uint8_t byte = (uint8_t)(value & 0x7F);
        value >>= 7;
        if (value != 0) byte |= 0x80;
        buf[len++] = byte;
    } while (value != 0);
    return len;
}

/* LEB128 encode signed integer (for type codes), return bytes written */
static int32_t encode_leb128_signed(uint8_t* buf, int64_t value) {
    int32_t len = 0;
    int more = 1;
    while (more) {
        uint8_t byte = (uint8_t)(value & 0x7F);
        value >>= 7;
        /* Sign bit of byte is second high order bit (0x40) */
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

/* Encode text as Candid: LEB128 length + UTF-8 bytes */
static int32_t encode_candid_text_value(uint8_t* buf, const char* text) {
    uint32_t text_len = (uint32_t)strlen(text);
    int32_t offset = encode_leb128_unsigned(buf, text_len);
    memcpy(buf + offset, text, text_len);
    return offset + (int32_t)text_len;
}

/* Encode blob as Candid: LEB128 length + bytes */
static int32_t encode_candid_blob_value(uint8_t* buf, const uint8_t* data, uint32_t data_len) {
    int32_t offset = encode_leb128_unsigned(buf, data_len);
    memcpy(buf + offset, data, data_len);
    return offset + (int32_t)data_len;
}

/*
 * Build Candid-encoded HttpRequestArgs for a simple GET request
 * Minimal encoding to test HTTP outcall infrastructure
 */
static int32_t build_simple_get_request(uint8_t* buf) {
    /*
     * Simplified GET request to httpbin.org/get
     *
     * Type indices:
     * 0: record { value: text; name: text }  (http_header)
     * 1: vec type_0                           (headers)
     * 2: variant { get; head; post }          (method)
     * 3: opt nat64                            (max_response_bytes)
     * 4: vec nat8                             (blob for body)
     * 5: opt type_4                           (opt blob)
     * 6: opt reserved                         (for transform)
     * 7: HttpRequestArgs record
     */

    int32_t offset = 0;

    /* Magic header */
    buf[offset++] = 'D'; buf[offset++] = 'I'; buf[offset++] = 'D'; buf[offset++] = 'L';

    /* Type table: 8 types */
    buf[offset++] = 8;

    /* Type 0: http_header = record { value: text; name: text }
     * Fields sorted by hash: value=0x31B87F71 < name=0x48FF724B */
    offset += encode_leb128_signed(buf + offset, -20);  /* record */
    offset += encode_leb128_unsigned(buf + offset, 2);  /* 2 fields */
    offset += encode_leb128_unsigned(buf + offset, 0x31B87F71);  /* value hash */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */
    offset += encode_leb128_unsigned(buf + offset, 0x48FF724B);  /* name hash */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */

    /* Type 1: vec http_header */
    offset += encode_leb128_signed(buf + offset, -19);  /* vec */
    offset += encode_leb128_unsigned(buf + offset, 0);  /* type index 0 */

    /* Type 2: variant { get; head; post }
     * Sorted by hash: get=0x004E8096 < head=0x450B2920 < post=0x4A5C8460 */
    offset += encode_leb128_signed(buf + offset, -21);  /* variant */
    offset += encode_leb128_unsigned(buf + offset, 3);  /* 3 variants */
    offset += encode_leb128_unsigned(buf + offset, 0x004E8096);  /* get */
    offset += encode_leb128_signed(buf + offset, -1);   /* null */
    offset += encode_leb128_unsigned(buf + offset, 0x450B2920);  /* head */
    offset += encode_leb128_signed(buf + offset, -1);   /* null */
    offset += encode_leb128_unsigned(buf + offset, 0x4A5C8460);  /* post */
    offset += encode_leb128_signed(buf + offset, -1);   /* null */

    /* Type 3: opt nat64 */
    offset += encode_leb128_signed(buf + offset, -18);  /* opt */
    offset += encode_leb128_signed(buf + offset, -8);   /* nat64 */

    /* Type 4: vec nat8 (blob) */
    offset += encode_leb128_signed(buf + offset, -19);  /* vec */
    offset += encode_leb128_signed(buf + offset, -5);   /* nat8 */

    /* Type 5: opt blob */
    offset += encode_leb128_signed(buf + offset, -18);  /* opt */
    offset += encode_leb128_unsigned(buf + offset, 4);  /* type index 4 */

    /* Type 6: opt reserved (for transform) */
    offset += encode_leb128_signed(buf + offset, -18);  /* opt */
    offset += encode_leb128_signed(buf + offset, -16);  /* reserved */

    /* Type 7: HttpRequestArgs record - 6 fields */
    offset += encode_leb128_signed(buf + offset, -20);  /* record */
    offset += encode_leb128_unsigned(buf + offset, 6);  /* 6 fields */
    /* url */
    offset += encode_leb128_unsigned(buf + offset, 0x00592B6F);
    offset += encode_leb128_signed(buf + offset, -15);  /* text */
    /* method */
    offset += encode_leb128_unsigned(buf + offset, 0x095AF6E1);
    offset += encode_leb128_unsigned(buf + offset, 2);  /* type 2 */
    /* max_response_bytes */
    offset += encode_leb128_unsigned(buf + offset, 0x12762B68);
    offset += encode_leb128_unsigned(buf + offset, 3);  /* type 3 */
    /* body */
    offset += encode_leb128_unsigned(buf + offset, 0x411B7AA2);
    offset += encode_leb128_unsigned(buf + offset, 5);  /* type 5 */
    /* transform */
    offset += encode_leb128_unsigned(buf + offset, 0x45932D6C);
    offset += encode_leb128_unsigned(buf + offset, 6);  /* type 6 */
    /* headers */
    offset += encode_leb128_unsigned(buf + offset, 0x63085246);
    offset += encode_leb128_unsigned(buf + offset, 1);  /* type 1 */

    /* Type sequence: 1 argument of type 7 */
    buf[offset++] = 1;
    offset += encode_leb128_unsigned(buf + offset, 7);

    /* Values in field hash order: url, method, max_response_bytes, body, transform, headers */

    /* url */
    const char* url = "https://httpbin.org/get";
    offset += encode_candid_text_value(buf + offset, url);

    /* method: get (index 0) */
    offset += encode_leb128_unsigned(buf + offset, 0);

    /* max_response_bytes: None */
    buf[offset++] = 0;

    /* body: None */
    buf[offset++] = 0;

    /* transform: None */
    buf[offset++] = 0;

    /* headers: empty vec */
    buf[offset++] = 0;

    return offset;
}

/*
 * Build Candid-encoded HttpRequestArgs for eth_blockNumber POST
 */
static int32_t build_eth_block_number_request(uint8_t* buf) {
    int32_t offset = 0;

    /* Magic header */
    buf[offset++] = 'D'; buf[offset++] = 'I'; buf[offset++] = 'D'; buf[offset++] = 'L';

    /* Type table: 8 types */
    buf[offset++] = 8;

    /* Type 0: http_header = record { value: text; name: text } */
    offset += encode_leb128_signed(buf + offset, -20);  /* record */
    offset += encode_leb128_unsigned(buf + offset, 2);  /* 2 fields */
    offset += encode_leb128_unsigned(buf + offset, 0x31B87F71);  /* value hash */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */
    offset += encode_leb128_unsigned(buf + offset, 0x48FF724B);  /* name hash */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */

    /* Type 1: vec http_header */
    offset += encode_leb128_signed(buf + offset, -19);
    offset += encode_leb128_unsigned(buf + offset, 0);

    /* Type 2: variant { get; head; post } */
    offset += encode_leb128_signed(buf + offset, -21);
    offset += encode_leb128_unsigned(buf + offset, 3);
    offset += encode_leb128_unsigned(buf + offset, 0x004E8096);  /* get */
    offset += encode_leb128_signed(buf + offset, -1);
    offset += encode_leb128_unsigned(buf + offset, 0x450B2920);  /* head */
    offset += encode_leb128_signed(buf + offset, -1);
    offset += encode_leb128_unsigned(buf + offset, 0x4A5C8460);  /* post */
    offset += encode_leb128_signed(buf + offset, -1);

    /* Type 3: opt nat64 */
    offset += encode_leb128_signed(buf + offset, -18);
    offset += encode_leb128_signed(buf + offset, -8);

    /* Type 4: vec nat8 */
    offset += encode_leb128_signed(buf + offset, -19);
    offset += encode_leb128_signed(buf + offset, -5);

    /* Type 5: opt blob */
    offset += encode_leb128_signed(buf + offset, -18);
    offset += encode_leb128_unsigned(buf + offset, 4);

    /* Type 6: opt reserved */
    offset += encode_leb128_signed(buf + offset, -18);
    offset += encode_leb128_signed(buf + offset, -16);

    /* Type 7: HttpRequestArgs */
    offset += encode_leb128_signed(buf + offset, -20);
    offset += encode_leb128_unsigned(buf + offset, 6);
    offset += encode_leb128_unsigned(buf + offset, 0x00592B6F);
    offset += encode_leb128_signed(buf + offset, -15);
    offset += encode_leb128_unsigned(buf + offset, 0x095AF6E1);
    offset += encode_leb128_unsigned(buf + offset, 2);
    offset += encode_leb128_unsigned(buf + offset, 0x12762B68);
    offset += encode_leb128_unsigned(buf + offset, 3);
    offset += encode_leb128_unsigned(buf + offset, 0x411B7AA2);
    offset += encode_leb128_unsigned(buf + offset, 5);
    offset += encode_leb128_unsigned(buf + offset, 0x45932D6C);
    offset += encode_leb128_unsigned(buf + offset, 6);
    offset += encode_leb128_unsigned(buf + offset, 0x63085246);
    offset += encode_leb128_unsigned(buf + offset, 1);

    /* Type sequence */
    buf[offset++] = 1;
    offset += encode_leb128_unsigned(buf + offset, 7);

    /* Values: url, method, max_response_bytes, body, transform, headers */
    /* Use Base Mainnet for HTTP Outcall E2E test */
    const char* rpc_url = "https://mainnet.base.org";
    offset += encode_candid_text_value(buf + offset, rpc_url);

    /* method: post (index 2) */
    offset += encode_leb128_unsigned(buf + offset, 2);

    /* max_response_bytes: Some(2048)
     * nat64 is encoded as 8 bytes little-endian, NOT LEB128! */
    buf[offset++] = 1;  /* Some */
    uint64_t max_bytes = 2048;
    buf[offset++] = (uint8_t)(max_bytes & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 8) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 16) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 24) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 32) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 40) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 48) & 0xFF);
    buf[offset++] = (uint8_t)((max_bytes >> 56) & 0xFF);

    /* body: Some(json-rpc) */
    const char* json_body = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}";
    buf[offset++] = 1;
    offset += encode_candid_blob_value(buf + offset, (const uint8_t*)json_body, (uint32_t)strlen(json_body));

    /* transform: None */
    buf[offset++] = 0;

    /* headers: 1 header (Content-Type) */
    buf[offset++] = 1;
    offset += encode_candid_text_value(buf + offset, "application/json");
    offset += encode_candid_text_value(buf + offset, "Content-Type");

    return offset;
}

/* Forward declarations for exported callback functions
 * IC callbacks take an env parameter (i32) even if unused */
extern void http_reply_callback(int32_t env);
extern void http_reject_callback(int32_t env);

/* =============================================================================
 * EVM RPC Canister Integration
 * ============================================================================= */

/* EVM RPC canister principal (mainnet fiduciary subnet)
 * Principal: 7hfb6-caaaa-aaaar-qadga-cai
 * Decoded bytes (without CRC32 checksum): 00000000023000cc0101 (10 bytes) */
static const uint8_t EVM_RPC_CANISTER_ID[] = {
    0x00, 0x00, 0x00, 0x00, 0x02, 0x30, 0x00, 0xcc, 0x01, 0x01
};
static const int32_t EVM_RPC_CANISTER_ID_LEN = 10;

/* NOTE: build_evm_rpc_request and build_evm_rpc_request_multichain have been
 * replaced by Idris2's type-safe Candid encoder in src/Candid/EvmRpc.idr.
 *
 * Benefits of Idris2 implementation:
 * - Chain/Provider hashes are derived from names, not hardcoded magic numbers
 * - Variant indices are automatically calculated from hash-sorted lists
 * - Unknown chain IDs return Nothing instead of silently defaulting to EthMainnet
 * - Adding new chains requires only updating the Chain ADT
 *
 * Use encode_evm_rpc_idris2() instead.
 */

/*
 * Check if JSON response contains an RPC error
 * Returns: 0 = success, 1 = retryable error, 2 = permanent error
 */
static int32_t check_rpc_error(const char* json, int32_t len) {
    /* Look for "error" field in JSON-RPC response */
    for (int32_t i = 0; i < len - 8; i++) {
        if (json[i] == '"' && json[i+1] == 'e' && json[i+2] == 'r' &&
            json[i+3] == 'r' && json[i+4] == 'o' && json[i+5] == 'r' && json[i+6] == '"') {
            /* Found "error" field - check error code */
            /* Look for "code": */
            for (int32_t j = i + 7; j < len - 7; j++) {
                if (json[j] == '"' && json[j+1] == 'c' && json[j+2] == 'o' &&
                    json[j+3] == 'd' && json[j+4] == 'e' && json[j+5] == '"') {
                    /* Extract error code number */
                    int32_t code = 0;
                    int negative = 0;
                    for (int32_t k = j + 7; k < len && k < j + 20; k++) {
                        if (json[k] == '-') { negative = 1; continue; }
                        if (json[k] >= '0' && json[k] <= '9') {
                            code = code * 10 + (json[k] - '0');
                        } else if (json[k] != ' ' && json[k] != ':') {
                            break;
                        }
                    }
                    if (negative) code = -code;

                    /* Classify error:
                     * -32700: Parse error (permanent)
                     * -32600: Invalid request (permanent)
                     * -32601: Method not found (permanent)
                     * -32602: Invalid params (permanent)
                     * -32603: Internal error (retryable)
                     * -32000 to -32099: Server errors (usually retryable)
                     * -32001: Resource not found (permanent)
                     * -32002: Resource unavailable (retryable)
                     * -32003: Transaction rejected (permanent)
                     */
                    if (code == -32700 || code == -32600 || code == -32601 ||
                        code == -32602 || code == -32001 || code == -32003) {
                        return 2;  /* Permanent error */
                    }
                    return 1;  /* Retryable error */
                }
            }
            return 1;  /* Error without code, assume retryable */
        }
    }
    return 0;  /* No error */
}

/* Callback for EVM RPC response */
__attribute__((used, visibility("default"), export_name("evm_rpc_reply_callback")))
void evm_rpc_reply_callback(int32_t env) {
    (void)env;
    debug("OUC: evm_rpc_reply_callback");

    /* Read response Candid */
    int32_t arg_size = ic0_msg_arg_data_size();
    static uint8_t response_buf[4096];
    if (arg_size > (int32_t)sizeof(response_buf)) arg_size = sizeof(response_buf);
    if (arg_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)response_buf, 0, arg_size);
    }

    /* Parse RequestResult = variant { Ok : text; Err : RpcError }
     * For simplicity, just extract the text from Ok variant */

    /* Find the text content after type table */
    /* DIDL + type table + type seq + variant tag + text */
    int32_t offset = 4;  /* Skip DIDL */
    int32_t new_offset;

    /* Skip type count */
    parse_leb128(offset, &new_offset);
    offset = new_offset;

    /* Skip type definitions (simplified - assume small) */
    /* For RequestResult, there's usually 1-2 types */
    /* Just scan for the text data which starts after variant tag */

    /* Look for the JSON response starting with { or error */
    char result[600];
    int len = 0;
    int json_found = 0;
    int32_t json_start_idx = 0;

    /* Search for JSON-RPC result pattern in response */
    for (int32_t i = 10; i < arg_size - 10; i++) {
        if (response_buf[i] == '{' && response_buf[i+1] == '"') {
            /* Found JSON start, extract until closing } */
            json_start_idx = i;
            json_found = 1;
            int brace_count = 0;
            for (int32_t j = i; j < arg_size && len < 500; j++) {
                if (response_buf[j] == '{') brace_count++;
                if (response_buf[j] == '}') brace_count--;
                result[len++] = (char)response_buf[j];
                if (brace_count == 0) break;
            }
            break;
        }
    }

    if (!json_found) {
        /* No JSON found, return structured error */
        const char* prefix = "{\"error\":\"no_json_found\",\"errorType\":\"parse\",\"retryable\":false,\"rawLen\":";
        while (*prefix) result[len++] = *prefix++;
        if (arg_size >= 1000) result[len++] = '0' + (char)((arg_size / 1000) % 10);
        if (arg_size >= 100) result[len++] = '0' + (char)((arg_size / 100) % 10);
        if (arg_size >= 10) result[len++] = '0' + (char)((arg_size / 10) % 10);
        result[len++] = '0' + (char)(arg_size % 10);
        result[len++] = '}';
    } else {
        /* Check for RPC-level errors in the JSON response */
        int32_t error_type = check_rpc_error(result, len);
        if (error_type > 0) {
            /* Wrap the error response with metadata */
            char wrapped[600];
            int wlen = 0;
            const char* prefix = "{\"rpcResponse\":";
            while (*prefix) wrapped[wlen++] = *prefix++;

            for (int i = 0; i < len && wlen < 500; i++) {
                wrapped[wlen++] = result[i];
            }

            if (error_type == 1) {
                const char* suffix = ",\"errorType\":\"rpc\",\"retryable\":true}";
                while (*suffix) wrapped[wlen++] = *suffix++;
            } else {
                const char* suffix = ",\"errorType\":\"rpc\",\"retryable\":false}";
                while (*suffix) wrapped[wlen++] = *suffix++;
            }
            wrapped[wlen] = '\0';

            /* Copy back */
            len = 0;
            for (int i = 0; wrapped[i] && len < 590; i++) {
                result[len++] = wrapped[i];
            }
        }
    }

    result[len] = '\0';
    reply_candid_text(result);
}

/*
 * Callback for EVM RPC rejection
 *
 * IC Reject Codes:
 *   1 = SysFatal: System fatal error (not retryable)
 *   2 = SysTransient: System transient error (retryable)
 *   3 = DestinationInvalid: Destination invalid (not retryable)
 *   4 = CanisterReject: Canister explicitly rejected (check message)
 *   5 = CanisterError: Canister trapped/error (might be retryable)
 */
__attribute__((used, visibility("default"), export_name("evm_rpc_reject_callback")))
void evm_rpc_reject_callback(int32_t env) {
    (void)env;
    debug("OUC: evm_rpc_reject_callback");

    int32_t reject_code = ic0_msg_reject_code();
    int32_t msg_size = ic0_msg_reject_msg_size();

    /* Determine if error is retryable based on reject code */
    int retryable = (reject_code == 2 || reject_code == 5);  /* SysTransient or CanisterError */

    /* Get error type name */
    const char* error_type;
    switch (reject_code) {
        case 1: error_type = "sys_fatal"; break;
        case 2: error_type = "sys_transient"; break;
        case 3: error_type = "dest_invalid"; break;
        case 4: error_type = "canister_reject"; break;
        case 5: error_type = "canister_error"; break;
        default: error_type = "unknown"; break;
    }

    char response[512];
    int32_t len = 0;

    /* Build structured error response */
    const char* prefix = "{\"error\":\"evm_rpc_rejected\",\"code\":";
    while (prefix[len]) { response[len] = prefix[len]; len++; }

    if (reject_code >= 10) response[len++] = '0' + (char)((reject_code / 10) % 10);
    response[len++] = '0' + (char)(reject_code % 10);

    /* Add error type */
    const char* type_prefix = ",\"errorType\":\"";
    for (int i = 0; type_prefix[i]; i++) response[len++] = type_prefix[i];
    for (int i = 0; error_type[i]; i++) response[len++] = error_type[i];
    response[len++] = '"';

    /* Add retryable flag */
    if (retryable) {
        const char* retry = ",\"retryable\":true";
        for (int i = 0; retry[i]; i++) response[len++] = retry[i];
    } else {
        const char* retry = ",\"retryable\":false";
        for (int i = 0; retry[i]; i++) response[len++] = retry[i];
    }

    /* Add reject message if available */
    if (msg_size > 0 && msg_size < 250) {
        const char* msg_prefix = ",\"msg\":\"";
        for (int i = 0; msg_prefix[i]; i++) response[len++] = msg_prefix[i];

        char msg_buf[300];
        ic0_msg_reject_msg_copy((int32_t)(uintptr_t)msg_buf, 0, msg_size);
        for (int32_t i = 0; i < msg_size && len < 450; i++) {
            char c = msg_buf[i];
            if (c == '"' || c == '\\') response[len++] = '\\';
            if (c >= 32 && c < 127) response[len++] = c;
        }
        response[len++] = '"';
    }

    response[len++] = '}';
    response[len] = '\0';
    reply_candid_text(response);
}

/* =============================================================================
 * A-Life Economics: Donation Methods
 * ============================================================================= */

/* Donate cycles to a protocol (protocol_id: OU contract address)
 * Cycles must be attached to the call */
__attribute__((used, visibility("default"), export_name("canister_update donate")))
void canister_update_donate(void) {
    debug("OUC: donate");

    /* Parse protocol_id from Candid argument (uses global text_arg_buf) */
    int32_t len = parse_candid_text_arg();

    if (len == 0) {
        reply_candid_text("{\"error\":\"invalid_protocol_id\"}");
        return;
    }

    debug("OUC: donate to protocol");

    /* Accept cycles and donate to protocol */
    uint64_t new_balance = ouc_accept_and_donate(text_arg_buf);

    /* Build response JSON */
    char response[256];
    int rlen = 0;
    const char* p = "{\"protocolId\":\"";
    while (*p) response[rlen++] = *p++;
    for (int i = 0; text_arg_buf[i] && rlen < 200; i++) {
        response[rlen++] = text_arg_buf[i];
    }
    p = "\",\"balance\":";
    while (*p) response[rlen++] = *p++;

    /* Convert balance to decimal string */
    char balance_str[24];
    int blen = 0;
    uint64_t tmp = new_balance;
    if (tmp == 0) {
        balance_str[blen++] = '0';
    } else {
        while (tmp > 0) {
            balance_str[blen++] = '0' + (char)(tmp % 10);
            tmp /= 10;
        }
    }
    /* Reverse */
    for (int i = blen - 1; i >= 0; i--) {
        response[rlen++] = balance_str[i];
    }

    p = ",\"tier\":";
    while (*p) response[rlen++] = *p++;
    uint8_t tier = ouc_get_protocol_tier(text_arg_buf);
    response[rlen++] = '0' + tier;

    response[rlen++] = '}';
    response[rlen] = '\0';

    reply_candid_text(response);
}

/* Query protocol balance */
__attribute__((used, visibility("default"), export_name("canister_query getProtocolBalance")))
void canister_query_getProtocolBalance(void) {
    debug("OUC: getProtocolBalance");

    /* Parse protocol_id from Candid argument (uses global text_arg_buf) */
    int32_t len = parse_candid_text_arg();

    if (len == 0) {
        reply_candid_nat(0);
        return;
    }

    uint64_t balance = ouc_get_protocol_balance(text_arg_buf);
    reply_candid_nat(balance);
}

/* Query protocol tier */
__attribute__((used, visibility("default"), export_name("canister_query getProtocolTier")))
void canister_query_getProtocolTier(void) {
    debug("OUC: getProtocolTier");

    /* Parse protocol_id from Candid argument (uses global text_arg_buf) */
    int32_t len = parse_candid_text_arg();

    if (len == 0) {
        reply_candid_nat(0);
        return;
    }

    uint8_t tier = ouc_get_protocol_tier(text_arg_buf);
    reply_candid_nat((uint64_t)tier);
}

/* Query total protocol count */
__attribute__((used, visibility("default"), export_name("canister_query getProtocolCount")))
void canister_query_getProtocolCount(void) {
    debug("OUC: getProtocolCount");
    uint32_t count = ouc_get_protocol_count();
    reply_candid_nat((uint64_t)count);
}

/* =============================================================================
 * EVM Event Indexer Query Methods (CMD 30-33)
 * ============================================================================= */

/* Get recent OUC events count */
__attribute__((used, visibility("default"), export_name("canister_query getOucEvents")))
void canister_query_getOucEvents(void) {
    debug("OUC: getOucEvents");

    /* Parse limit (nat) from Candid argument */
    uint32_t arg_size = ic0_msg_arg_data_size();
    if (arg_size < 5) {
        reply_candid_nat(0);
        return;
    }

    uint8_t arg_buf[64];
    ic0_msg_arg_data_copy((int32_t)(uintptr_t)arg_buf, 0, arg_size < 64 ? arg_size : 64);

    /* Simple nat parsing: skip DIDL header (4 bytes), read LEB128 nat */
    uint64_t limit = 10;
    if (arg_size > 4) {
        limit = (uint64_t)arg_buf[4];  /* Simplified: single byte nat */
    }

    int32_t count = call_idris2_1arg(CMD_GET_OUC_EVENTS, (int32_t)limit);
    reply_candid_nat((uint64_t)(count >= 0 ? count : 0));
}

/* Get events for a specific proposal */
__attribute__((used, visibility("default"), export_name("canister_query getProposalEvents")))
void canister_query_getProposalEvents(void) {
    debug("OUC: getProposalEvents");

    /* Parse proposalId (nat) from Candid argument */
    uint32_t arg_size = ic0_msg_arg_data_size();
    if (arg_size < 5) {
        reply_candid_nat(0);
        return;
    }

    uint8_t arg_buf[64];
    ic0_msg_arg_data_copy((int32_t)(uintptr_t)arg_buf, 0, arg_size < 64 ? arg_size : 64);

    uint64_t proposal_id = 0;
    if (arg_size > 4) {
        proposal_id = (uint64_t)arg_buf[4];  /* Simplified: single byte nat */
    }

    int32_t count = call_idris2_1arg(CMD_GET_PROPOSAL_EVENTS, (int32_t)proposal_id);
    reply_candid_nat((uint64_t)(count >= 0 ? count : 0));
}

/* Get dashboard summary (total event count) */
__attribute__((used, visibility("default"), export_name("canister_query getDashboardSummary")))
void canister_query_getDashboardSummary(void) {
    debug("OUC: getDashboardSummary");
    int32_t count = call_idris2(CMD_GET_DASHBOARD_SUMMARY);
    reply_candid_nat((uint64_t)(count >= 0 ? count : 0));
}

/* Store test event (for development/testing) */
__attribute__((used, visibility("default"), export_name("canister_update storeTestEvent")))
void canister_update_storeTestEvent(void) {
    debug("OUC: storeTestEvent");

    /* Parse blockNumber and eventType (nat, nat) from Candid argument */
    uint32_t arg_size = ic0_msg_arg_data_size();
    if (arg_size < 6) {
        reply_candid_nat(0);
        return;
    }

    uint8_t arg_buf[64];
    ic0_msg_arg_data_copy((int32_t)(uintptr_t)arg_buf, 0, arg_size < 64 ? arg_size : 64);

    /* Simplified parsing: skip DIDL header, read two single-byte nats */
    uint64_t block_num = arg_size > 4 ? (uint64_t)arg_buf[4] : 1;
    uint64_t event_type = arg_size > 5 ? (uint64_t)arg_buf[5] : 0;

    int32_t new_count = call_idris2_2arg(CMD_STORE_TEST_EVENT, (int32_t)block_num, (int32_t)event_type);
    reply_candid_nat((uint64_t)(new_count >= 0 ? new_count : 0));
}

/* Test method: Call eth_blockNumber via EVM RPC canister */
__attribute__((used, visibility("default"), export_name("canister_update testEvmRpc")))
void canister_update_testEvmRpc(void) {
    debug("OUC: testEvmRpc - calling EVM RPC canister");

    /* Build Candid arguments using Idris2 (type-safe) */
    const char* json_rpc = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}";
    int32_t candid_len = encode_evm_rpc_idris2(json_rpc, 8453 /* Base Mainnet */, 2000);
    if (candid_len < 0) {
        debug("OUC: Candid encoding failed");
        reply_candid_text("{\"error\":\"candid_encoding_failed\"}");
        return;
    }
    uint8_t* candid_buf = ouc_c_get_candid_buf();

    debug("OUC: EVM RPC candid built via Idris2");

    /* Setup call to EVM RPC canister */
    const char* method = "request";

    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = evm_rpc_reply_callback;
    callback_fn reject_cb = evm_rpc_reject_callback;

    ic0_call_new(
        (int32_t)(uintptr_t)EVM_RPC_CANISTER_ID, EVM_RPC_CANISTER_ID_LEN,
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),
        (int32_t)(uintptr_t)reply_cb, 0,
        (int32_t)(uintptr_t)reject_cb, 0
    );

    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);

    /* EVM RPC canister charges cycles for HTTP outcalls
     * Approximate cost: ~2B cycles for simple requests */
    ic0_call_cycles_add128(0, 10000000000ULL);  /* 10B cycles */

    int32_t result = ic0_call_perform();

    if (result != 0) {
        char err[64];
        int len = 0;
        const char* msg = "{\"error\":\"call_failed\",\"code\":";
        while (msg[len]) { err[len] = msg[len]; len++; }
        if (result < 0) { err[len++] = '-'; result = -result; }
        if (result >= 10) err[len++] = '0' + (char)((result / 10) % 10);
        err[len++] = '0' + (char)(result % 10);
        err[len++] = '}';
        err[len] = '\0';
        reply_candid_text(err);
    }
}

/* =============================================================================
 * ERC-7546 Dictionary Query (OU Monitoring)
 * ============================================================================= */

/* Stored query parameters for callback context */
static char g_query_dict_addr[44];      /* 0x + 40 hex chars + null */
static char g_query_selector[12];       /* 0x + 8 hex chars + null */

/*
 * Build eth_call JSON-RPC request for ERC-7546 Dictionary.getImplementation(bytes4)
 *
 * ERC-7546 Upgradeable Clone: getImplementation(bytes4) selector = 0xdc9cc645
 * (NOT ERC-2535 Diamond Standard which uses facetAddress)
 *
 * OUF (../idris2-ouf) uses ERC-7546, not ERC-2535.
 * Calldata = selector + 4-byte argument right-padded to 32 bytes
 */
static int32_t build_dict_query_json(char* buf, const char* dict_addr, const char* func_selector) {
    int32_t len = 0;
    const char* p;

    /* Build JSON-RPC request for eth_call */
    p = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"";
    while (*p) buf[len++] = *p++;

    /* Dictionary address (0x + 40 hex chars) */
    p = dict_addr;
    while (*p) buf[len++] = *p++;

    p = "\",\"data\":\"0xdc9cc645";  /* getImplementation(bytes4) selector (ERC-7546) */
    while (*p) buf[len++] = *p++;

    /* Function selector to query (skip 0x prefix, 8 hex chars) */
    p = func_selector;
    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
    for (int i = 0; i < 8 && p[i]; i++) buf[len++] = p[i];

    /* Pad to 32 bytes (remaining 56 hex chars of zeros) */
    for (int i = 0; i < 56; i++) buf[len++] = '0';

    p = "\"},\"latest\"],\"id\":1}";
    while (*p) buf[len++] = *p++;

    buf[len] = '\0';
    return len;
}

/* Callback for Dictionary query response */
__attribute__((used, visibility("default"), export_name("dict_query_reply_callback")))
void dict_query_reply_callback(int32_t env) {
    (void)env;
    debug("OUC: dict_query_reply_callback");

    /* Read response Candid */
    int32_t arg_size = ic0_msg_arg_data_size();
    static uint8_t response_buf[4096];
    if (arg_size > (int32_t)sizeof(response_buf)) arg_size = sizeof(response_buf);
    if (arg_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)response_buf, 0, arg_size);
    }

    /* Extract JSON result from response */
    char result[512];
    int len = 0;

    /* Search for "result":"0x... pattern in JSON-RPC response */
    int found_result = 0;
    for (int32_t i = 10; i < arg_size - 20; i++) {
        if (response_buf[i] == 'r' && response_buf[i+1] == 'e' &&
            response_buf[i+2] == 's' && response_buf[i+3] == 'u' &&
            response_buf[i+4] == 'l' && response_buf[i+5] == 't') {
            /* Found "result", look for hex value */
            for (int32_t j = i + 6; j < arg_size - 2; j++) {
                if (response_buf[j] == '0' && response_buf[j+1] == 'x') {
                    /* Extract hex string (64 chars for address) */
                    int32_t hex_start = j;
                    int32_t hex_len = 0;
                    while (j + hex_len < arg_size && hex_len < 66) {
                        char c = (char)response_buf[j + hex_len];
                        if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                            (c >= 'A' && c <= 'F') || c == 'x') {
                            hex_len++;
                        } else {
                            break;
                        }
                    }

                    /* Build response JSON with implementation address */
                    const char* prefix = "{\"dictionary\":\"";
                    const char* p = prefix;
                    while (*p) result[len++] = *p++;

                    p = g_query_dict_addr;
                    while (*p && len < 200) result[len++] = *p++;

                    p = "\",\"selector\":\"";
                    while (*p) result[len++] = *p++;

                    p = g_query_selector;
                    while (*p && len < 250) result[len++] = *p++;

                    p = "\",\"implementation\":\"0x";
                    while (*p) result[len++] = *p++;

                    /* Extract last 40 hex chars (address from 32-byte result) */
                    /* Result is 0x + 64 hex chars, address is last 40 */
                    int addr_start = (hex_len > 42) ? hex_len - 40 : 2;
                    for (int k = addr_start; k < hex_len && len < 450; k++) {
                        result[len++] = (char)response_buf[hex_start + k];
                    }

                    result[len++] = '"';
                    result[len++] = '}';
                    found_result = 1;
                    break;
                }
            }
            break;
        }
    }

    if (!found_result) {
        /* No result found, return error */
        const char* prefix = "{\"error\":\"no_result\",\"rawLen\":";
        const char* p = prefix;
        while (*p) result[len++] = *p++;
        if (arg_size >= 1000) result[len++] = '0' + (char)((arg_size / 1000) % 10);
        if (arg_size >= 100) result[len++] = '0' + (char)((arg_size / 100) % 10);
        if (arg_size >= 10) result[len++] = '0' + (char)((arg_size / 10) % 10);
        result[len++] = '0' + (char)(arg_size % 10);
        result[len++] = '}';
    }

    result[len] = '\0';
    reply_candid_text(result);
}

/* Callback for Dictionary query rejection */
__attribute__((used, visibility("default"), export_name("dict_query_reject_callback")))
void dict_query_reject_callback(int32_t env) {
    (void)env;
    debug("OUC: dict_query_reject_callback");

    int32_t reject_code = ic0_msg_reject_code();
    int32_t msg_size = ic0_msg_reject_msg_size();

    char response[512];
    int32_t len = 0;
    const char* prefix = "{\"error\":\"dict_query_rejected\",\"code\":";
    while (prefix[len]) { response[len] = prefix[len]; len++; }

    if (reject_code >= 10) response[len++] = '0' + (char)((reject_code / 10) % 10);
    response[len++] = '0' + (char)(reject_code % 10);

    if (msg_size > 0 && msg_size < 300) {
        const char* msg_prefix = ",\"msg\":\"";
        for (int i = 0; msg_prefix[i]; i++) response[len++] = msg_prefix[i];

        char msg_buf[300];
        ic0_msg_reject_msg_copy((int32_t)(uintptr_t)msg_buf, 0, msg_size);
        for (int32_t i = 0; i < msg_size && len < 480; i++) {
            char c = msg_buf[i];
            if (c == '"' || c == '\\') response[len++] = '\\';
            if (c >= 32 && c < 127) response[len++] = c;
        }
        response[len++] = '"';
    }

    response[len++] = '}';
    response[len] = '\0';
    reply_candid_text(response);
}

/*
 * Query ERC-7546 Dictionary for implementation address
 *
 * Arguments (Candid): (dictionary : text, selector : text) -> (text)
 * - dictionary: EVM address of the Dictionary contract (0x...)
 * - selector: 4-byte function selector to query (0x...)
 *
 * Returns JSON: {"dictionary":"0x...","selector":"0x...","implementation":"0x..."}
 */
__attribute__((used, visibility("default"), export_name("canister_update queryDictionary")))
void canister_update_queryDictionary(void) {
    debug("OUC: queryDictionary - ERC-7546 Dictionary query");

    /* Parse Candid arguments: (text, text)
     * Format: DIDL + type_table + arg_count=2 + text + text + len1 + str1 + len2 + str2
     */
    load_candid_args();

    if (arg_buf_size < 10) {
        reply_candid_text("{\"error\":\"invalid_args\"}");
        return;
    }

    /* Skip DIDL header */
    int32_t offset = 4;
    int32_t new_offset;

    /* Skip type table */
    uint64_t type_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    for (uint64_t i = 0; i < type_count; i++) {
        parse_leb128(offset, &new_offset);
        offset = new_offset;
    }

    /* Parse arg count */
    uint64_t arg_count = parse_leb128(offset, &new_offset);
    offset = new_offset;

    if (arg_count < 2) {
        reply_candid_text("{\"error\":\"need_2_args\"}");
        return;
    }

    /* Skip type codes (2x text = -15) */
    offset += 2;

    /* Parse first text (dictionary address) */
    uint64_t dict_len = parse_leb128(offset, &new_offset);
    offset = new_offset;
    if (dict_len > 43 || offset + dict_len > arg_buf_size) {
        reply_candid_text("{\"error\":\"dict_addr_too_long\"}");
        return;
    }

    for (uint64_t i = 0; i < dict_len && i < 43; i++) {
        g_query_dict_addr[i] = (char)arg_buf[offset + i];
    }
    g_query_dict_addr[dict_len] = '\0';
    offset += dict_len;

    /* Parse second text (selector) */
    uint64_t sel_len = parse_leb128(offset, &new_offset);
    offset = new_offset;
    if (sel_len > 11 || offset + sel_len > arg_buf_size) {
        reply_candid_text("{\"error\":\"selector_too_long\"}");
        return;
    }

    for (uint64_t i = 0; i < sel_len && i < 11; i++) {
        g_query_selector[i] = (char)arg_buf[offset + i];
    }
    g_query_selector[sel_len] = '\0';

    /* Build eth_call JSON-RPC */
    static char json_buf[512];
    build_dict_query_json(json_buf, g_query_dict_addr, g_query_selector);

    /* Build Candid for EVM RPC request using Idris2 (type-safe) */
    int32_t candid_len = encode_evm_rpc_idris2(json_buf, 1 /* EthMainnet */, 2000);
    if (candid_len < 0) {
        debug("OUC: Candid encoding failed");
        reply_candid_text("{\"error\":\"candid_encoding_failed\"}");
        return;
    }
    uint8_t* candid_buf = ouc_c_get_candid_buf();

    debug("OUC: Dictionary query candid built via Idris2");

    /* Setup call to EVM RPC canister */
    const char* method = "request";

    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = dict_query_reply_callback;
    callback_fn reject_cb = dict_query_reject_callback;

    ic0_call_new(
        (int32_t)(uintptr_t)EVM_RPC_CANISTER_ID, EVM_RPC_CANISTER_ID_LEN,
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),
        (int32_t)(uintptr_t)reply_cb, 0,
        (int32_t)(uintptr_t)reject_cb, 0
    );

    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);
    ic0_call_cycles_add128(0, 10000000000ULL);  /* 10B cycles */

    int32_t result = ic0_call_perform();

    if (result != 0) {
        char err[64];
        int len = 0;
        const char* msg = "{\"error\":\"call_failed\",\"code\":";
        while (msg[len]) { err[len] = msg[len]; len++; }
        if (result < 0) { err[len++] = '-'; result = -result; }
        if (result >= 10) err[len++] = '0' + (char)((result / 10) % 10);
        err[len++] = '0' + (char)(result % 10);
        err[len++] = '}';
        err[len] = '\0';
        reply_candid_text(err);
    }
}

/* Test method: Simple GET request via HTTP Outcall */
__attribute__((used, visibility("default"), export_name("canister_update testHttpGet")))
void canister_update_testHttpGet(void) {
    debug("OUC: testHttpGet - simple GET request");

    /* Build Candid-encoded HttpRequestArgs for GET */
    static uint8_t candid_buf[512];
    int32_t candid_len = build_simple_get_request(candid_buf);

    debug("OUC: http_request candid built for GET");

    /* Management canister = empty principal */
    const char* callee = "";
    const char* method = "http_request";

    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = http_reply_callback;
    callback_fn reject_cb = http_reject_callback;

    ic0_call_new(
        (int32_t)(uintptr_t)callee, 0,
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),
        (int32_t)(uintptr_t)reply_cb, 0,
        (int32_t)(uintptr_t)reject_cb, 0
    );

    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);
    ic0_call_cycles_add128(0, 30000000000ULL);

    int32_t result = ic0_call_perform();

    if (result != 0) {
        char err[64];
        int len = 0;
        const char* msg = "{\"error\":\"call_failed\",\"code\":";
        while (msg[len]) { err[len] = msg[len]; len++; }
        if (result < 0) { err[len++] = '-'; result = -result; }
        if (result >= 10) err[len++] = '0' + (char)((result / 10) % 10);
        err[len++] = '0' + (char)(result % 10);
        err[len++] = '}';
        err[len] = '\0';
        reply_candid_text(err);
    }
}

/* Test method: Call eth_blockNumber via HTTP Outcall */
__attribute__((used, visibility("default"), export_name("canister_update testEthBlockNumber")))
void canister_update_testEthBlockNumber(void) {
    debug("OUC: testEthBlockNumber");

    /* Build Candid-encoded HttpRequestArgs */
    static uint8_t candid_buf[1024];
    int32_t candid_len = build_eth_block_number_request(candid_buf);

    debug("OUC: http_request candid built");

    /* Management canister = empty principal */
    const char* callee = "";
    const char* method = "http_request";

    /* Get function pointer indices for callbacks
     * In WASM, function pointers become table indices
     * Use exported callback functions so IC can call them
     * IC callbacks have signature (i32) -> nil */
    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = http_reply_callback;
    callback_fn reject_cb = http_reject_callback;

    /* Setup inter-canister call with callbacks
     * The function pointers are automatically converted to table indices */
    ic0_call_new(
        (int32_t)(uintptr_t)callee, 0,                        /* callee: empty = mgmt canister */
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),  /* method: "http_request" */
        (int32_t)(uintptr_t)reply_cb, 0,  /* reply callback */
        (int32_t)(uintptr_t)reject_cb, 0  /* reject callback */
    );

    /* Append Candid-encoded arguments */
    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);

    /* Add cycles for HTTP request payment (~1-2B cycles for typical request) */
    /* Using 20 billion cycles to be safe */
    ic0_call_cycles_add128(0, 30000000000ULL);

    /* Perform the call */
    int32_t result = ic0_call_perform();

    if (result != 0) {
        /* Call failed to initiate - reply with error immediately */
        char err[64];
        int len = 0;
        const char* msg = "{\"error\":\"call_failed\",\"code\":";
        while (msg[len]) { err[len] = msg[len]; len++; }
        if (result < 0) { err[len++] = '-'; result = -result; }
        if (result >= 10) err[len++] = '0' + (char)((result / 10) % 10);
        err[len++] = '0' + (char)(result % 10);
        err[len++] = '}';
        err[len] = '\0';
        reply_candid_text(err);
    }
    /* If result == 0, call was initiated successfully.
     * DO NOT reply here - the callback will reply when response arrives.
     * Just return and let the IC runtime handle the async response. */
}

/* =============================================================================
 * HTTP Request Handler (Dashboard API)
 * ============================================================================= */

/*
 * Build Candid-encoded HttpResponse
 *
 * HttpResponse = record {
 *   status_code : nat16;
 *   headers : vec { record { text; text } };
 *   body : blob;
 * }
 *
 * Note: IC HTTP gateway expects specific encoding.
 * Using anonymous fields (0, 1) for header tuple, sorted by field hash for main record.
 */
static int32_t build_http_response(uint8_t* buf, uint16_t status_code,
                                    const char* content_type, const char* body) {
    int32_t offset = 0;

    /* DIDL header */
    buf[offset++] = 'D'; buf[offset++] = 'I';
    buf[offset++] = 'D'; buf[offset++] = 'L';

    /*
     * Type table: 4 types
     * In Candid, compound types (vec, opt, record) must be defined in the type table
     * and referenced by index. You cannot use type codes like -19 (vec) inline.
     *
     * Type 0: record { 0: text, 1: text }  - header tuple
     * Type 1: vec nat8  - blob for body
     * Type 2: vec type0 - vec of header tuples
     * Type 3: HttpResponse record
     */
    buf[offset++] = 4;  /* 4 types */

    /* Type 0: record { 0: text; 1: text } for header pair */
    offset += encode_leb128_signed(buf + offset, -20);  /* record type code */
    offset += encode_leb128_unsigned(buf + offset, 2);  /* 2 fields */
    offset += encode_leb128_unsigned(buf + offset, 0);  /* field hash 0 */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */
    offset += encode_leb128_unsigned(buf + offset, 1);  /* field hash 1 */
    offset += encode_leb128_signed(buf + offset, -15);  /* text */

    /* Type 1: vec nat8 (blob for body) */
    offset += encode_leb128_signed(buf + offset, -19);  /* vec */
    offset += encode_leb128_signed(buf + offset, -5);   /* nat8 */

    /* Type 2: vec type0 (headers) */
    offset += encode_leb128_signed(buf + offset, -19);  /* vec */
    offset += encode_leb128_unsigned(buf + offset, 0);  /* type 0 */

    /* Type 3: HttpResponse record
     * Fields sorted by hash:
     * body = 0x411b7aa2 (first) -> type 1
     * headers = 0x63085246 (second) -> type 2
     * status_code = 0xcf2c909a (third) -> nat16 */
    offset += encode_leb128_signed(buf + offset, -20);  /* record type code */
    offset += encode_leb128_unsigned(buf + offset, 3);  /* 3 fields */

    /* body (0x411b7aa2) -> type 1 (vec nat8) */
    offset += encode_leb128_unsigned(buf + offset, 0x411b7aa2);
    offset += encode_leb128_unsigned(buf + offset, 1);  /* type 1 */

    /* headers (0x63085246) -> type 2 (vec type0) */
    offset += encode_leb128_unsigned(buf + offset, 0x63085246);
    offset += encode_leb128_unsigned(buf + offset, 2);  /* type 2 */

    /* status_code (0xcf2c909a) -> nat16 (type code -6) */
    offset += encode_leb128_unsigned(buf + offset, 0xcf2c909a);
    offset += encode_leb128_signed(buf + offset, -6);   /* nat16 = -6 */

    /* Type sequence: 1 argument of type 3 (HttpResponse) */
    offset += encode_leb128_unsigned(buf + offset, 1);  /* 1 arg */
    offset += encode_leb128_unsigned(buf + offset, 3);  /* type 3 */

    /* Values (in hash-sorted order: body, headers, status_code) */

    /* body: blob */
    int32_t body_len = (int32_t)strlen(body);
    offset += encode_leb128_unsigned(buf + offset, body_len);
    for (int i = 0; i < body_len; i++) buf[offset++] = body[i];

    /* headers: vec { (key, value) } */
    offset += encode_leb128_unsigned(buf + offset, 1);  /* 1 header */
    /* Header tuple: (key, value) */
    const char* header_key = "Content-Type";
    int32_t key_len = (int32_t)strlen(header_key);
    offset += encode_leb128_unsigned(buf + offset, key_len);
    for (int i = 0; i < key_len; i++) buf[offset++] = header_key[i];
    int32_t ct_len = (int32_t)strlen(content_type);
    offset += encode_leb128_unsigned(buf + offset, ct_len);
    for (int i = 0; i < ct_len; i++) buf[offset++] = content_type[i];

    /* status_code: nat16 (2 bytes little-endian) */
    buf[offset++] = (uint8_t)(status_code & 0xFF);
    buf[offset++] = (uint8_t)((status_code >> 8) & 0xFF);

    return offset;
}

/*
 * HTTP Request handler (canister_query http_request)
 *
 * Serves:
 *   /api/status - JSON status endpoint
 *   / or /dashboard - HTML dashboard
 */
__attribute__((used, visibility("default"), export_name("canister_query http_request")))
void canister_query_http_request(void) {
    debug("OUC: http_request query");

    /* Parse HttpRequest to extract URL path */
    load_candid_args();

    /* Extract URL from Candid (simplified: look for path after first '/') */
    char url_path[128] = "/";
    int path_len = 1;

    /* Search for URL in request (after method field) */
    for (int32_t i = 10; i < arg_buf_size - 10; i++) {
        if (arg_buf[i] == '/' && (i == 0 || arg_buf[i-1] < 32 || arg_buf[i-1] > 126)) {
            /* Found path start */
            for (int j = 0; j < 127 && i + j < arg_buf_size; j++) {
                char c = (char)arg_buf[i + j];
                if (c == '?' || c == ' ' || c == '\0' || c < 32) break;
                url_path[j] = c;
                path_len = j + 1;
            }
            url_path[path_len] = '\0';
            break;
        }
    }

    debug("OUC: URL path extracted");

    static uint8_t response_buf[4096];
    int32_t response_len;

    /* Route based on path */
    if (path_len >= 11 && url_path[0] == '/' && url_path[1] == 'a' &&
        url_path[2] == 'p' && url_path[3] == 'i' && url_path[4] == '/' &&
        url_path[5] == 's' && url_path[6] == 't' && url_path[7] == 'a' &&
        url_path[8] == 't' && url_path[9] == 'u' && url_path[10] == 's') {
        /* /api/status - JSON status */
        int64_t auditor_count = ouc_get_auditor_count();
        int64_t proposal_count = ouc_get_proposal_count();

        char json[512];
        int len = 0;
        const char* p;

        p = "{\"canister\":\"nrkou-hqaaa-aaaah-qq6qa-cai\",\"status\":\"running\",\"version\":1,\"auditors\":";
        while (*p) json[len++] = *p++;

        /* auditor count */
        if (auditor_count >= 100) json[len++] = '0' + (char)((auditor_count / 100) % 10);
        if (auditor_count >= 10) json[len++] = '0' + (char)((auditor_count / 10) % 10);
        json[len++] = '0' + (char)(auditor_count % 10);

        p = ",\"proposals\":";
        while (*p) json[len++] = *p++;

        /* proposal count */
        if (proposal_count >= 100) json[len++] = '0' + (char)((proposal_count / 100) % 10);
        if (proposal_count >= 10) json[len++] = '0' + (char)((proposal_count / 10) % 10);
        json[len++] = '0' + (char)(proposal_count % 10);

        p = ",\"features\":[\"queryDictionary\",\"testEvmRpc\",\"economics\"]}";
        while (*p) json[len++] = *p++;
        json[len] = '\0';

        response_len = build_http_response(response_buf, 200, "application/json", json);
    } else {
        /* Default: HTML dashboard */
        const char* html =
            "<!DOCTYPE html><html><head><title>OUC Dashboard</title>"
            "<style>body{font-family:system-ui;max-width:800px;margin:40px auto;padding:0 20px;}"
            "h1{color:#333}pre{background:#f5f5f5;padding:15px;border-radius:5px;overflow:auto;}"
            ".status{color:#22c55e;font-weight:bold}</style></head>"
            "<body><h1>OUC Dashboard</h1>"
            "<p>Canister ID: <code>nrkou-hqaaa-aaaah-qq6qa-cai</code></p>"
            "<p>Status: <span class=\"status\">Running</span></p>"
            "<h2>API Endpoints</h2><ul>"
            "<li><a href=\"/api/status\">/api/status</a> - JSON status</li></ul>"
            "<h2>Canister Methods</h2><ul>"
            "<li><code>queryDictionary(dict, selector)</code> - Query ERC-2535 Diamond facet</li>"
            "<li><code>testEvmRpc()</code> - Test EVM RPC integration</li>"
            "<li><code>getVersion()</code> - Get canister version</li></ul>"
            "</body></html>";

        response_len = build_http_response(response_buf, 200, "text/html", html);
    }

    ic0_msg_reply_data_append((int32_t)(uintptr_t)response_buf, response_len);
    ic0_msg_reply();
}

/* =============================================================================
 * EVM Contract Monitoring Infrastructure
 *
 * Monitors ERC-7546 Dictionary contracts for implementation changes.
 * Stores snapshots of implementation addresses and detects changes.
 * ============================================================================= */

/* Maximum monitored contracts */
#define MAX_MONITORED_CONTRACTS 16
#define MAX_MONITORED_SELECTORS 8

/* Monitored contract entry */
typedef struct {
    char dictionary[43];           /* "0x" + 40 hex chars + null */
    char selectors[MAX_MONITORED_SELECTORS][11];  /* "0x" + 8 hex chars + null */
    char implementations[MAX_MONITORED_SELECTORS][43];  /* Last known implementation */
    int32_t selector_count;
    int32_t chain_id;
    int64_t last_checked;          /* Timestamp of last check */
    int32_t active;
} MonitoredContract;

/* Global monitoring state (C-backed, persists across calls) */
static MonitoredContract g_monitored_contracts[MAX_MONITORED_CONTRACTS];
static int32_t g_monitored_count = 0;
static int64_t g_last_monitor_heartbeat = 0;
static int32_t g_detected_changes = 0;

/*
 * Register a contract for monitoring
 *
 * Arguments (Candid): (dictionary : text, selector : text, chainId : nat32) -> (text)
 */
__attribute__((used, visibility("default"), export_name("canister_update registerMonitor")))
void canister_update_registerMonitor(void) {
    debug("OUC: registerMonitor");

    load_candid_args();

    if (arg_buf_size < 10) {
        reply_candid_text("{\"error\":\"invalid_args\"}");
        return;
    }

    /* Parse arguments: dictionary address, selector, chain_id */
    int32_t offset = 4;  /* Skip DIDL */
    int32_t new_offset;

    /* Skip type table */
    uint64_t type_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    for (uint64_t i = 0; i < type_count; i++) {
        parse_leb128(offset, &new_offset);
        offset = new_offset;
    }

    /* Skip arg count and type codes */
    parse_leb128(offset, &new_offset);
    offset = new_offset + 3;  /* 3 type codes: text, text, nat32 */

    /* Parse dictionary address */
    uint64_t dict_len = parse_leb128(offset, &new_offset);
    offset = new_offset;
    char dict_addr[43] = {0};
    for (uint64_t i = 0; i < dict_len && i < 42; i++) {
        dict_addr[i] = (char)arg_buf[offset + i];
    }
    offset += dict_len;

    /* Parse selector */
    uint64_t sel_len = parse_leb128(offset, &new_offset);
    offset = new_offset;
    char selector[11] = {0};
    for (uint64_t i = 0; i < sel_len && i < 10; i++) {
        selector[i] = (char)arg_buf[offset + i];
    }
    offset += sel_len;

    /* Parse chain_id (nat32 = 4 bytes little-endian) */
    int32_t chain_id = 0;
    if (offset + 4 <= arg_buf_size) {
        chain_id = arg_buf[offset] | (arg_buf[offset+1] << 8) |
                   (arg_buf[offset+2] << 16) | (arg_buf[offset+3] << 24);
    }

    /* Find or create entry for this dictionary */
    int32_t idx = -1;
    for (int32_t i = 0; i < g_monitored_count; i++) {
        int match = 1;
        for (int j = 0; j < 42 && dict_addr[j]; j++) {
            if (g_monitored_contracts[i].dictionary[j] != dict_addr[j]) {
                match = 0;
                break;
            }
        }
        if (match && g_monitored_contracts[i].chain_id == chain_id) {
            idx = i;
            break;
        }
    }

    if (idx < 0) {
        /* New contract */
        if (g_monitored_count >= MAX_MONITORED_CONTRACTS) {
            reply_candid_text("{\"error\":\"max_contracts_reached\"}");
            return;
        }
        idx = g_monitored_count++;
        for (int j = 0; j < 43; j++) {
            g_monitored_contracts[idx].dictionary[j] = dict_addr[j];
        }
        g_monitored_contracts[idx].chain_id = chain_id;
        g_monitored_contracts[idx].selector_count = 0;
        g_monitored_contracts[idx].active = 1;
        g_monitored_contracts[idx].last_checked = 0;
    }

    /* Add selector if not already present */
    MonitoredContract* mc = &g_monitored_contracts[idx];
    int sel_exists = 0;
    for (int32_t i = 0; i < mc->selector_count; i++) {
        int match = 1;
        for (int j = 0; j < 10 && selector[j]; j++) {
            if (mc->selectors[i][j] != selector[j]) {
                match = 0;
                break;
            }
        }
        if (match) {
            sel_exists = 1;
            break;
        }
    }

    if (!sel_exists && mc->selector_count < MAX_MONITORED_SELECTORS) {
        int sidx = mc->selector_count++;
        for (int j = 0; j < 11; j++) {
            mc->selectors[sidx][j] = selector[j];
        }
        /* Initialize implementation as empty */
        mc->implementations[sidx][0] = '\0';
    }

    /* Build response */
    char response[256];
    int len = 0;
    const char* p = "{\"status\":\"registered\",\"contractIndex\":";
    while (*p) response[len++] = *p++;
    if (idx >= 10) response[len++] = '0' + (idx / 10);
    response[len++] = '0' + (idx % 10);
    p = ",\"selectorCount\":";
    while (*p) response[len++] = *p++;
    response[len++] = '0' + mc->selector_count;
    p = ",\"totalContracts\":";
    while (*p) response[len++] = *p++;
    if (g_monitored_count >= 10) response[len++] = '0' + (g_monitored_count / 10);
    response[len++] = '0' + (g_monitored_count % 10);
    response[len++] = '}';
    response[len] = '\0';

    reply_candid_text(response);
}

/*
 * Get monitoring status
 *
 * Returns JSON with all monitored contracts and their status
 */
__attribute__((used, visibility("default"), export_name("canister_query getMonitoringStatus")))
void canister_query_getMonitoringStatus(void) {
    debug("OUC: getMonitoringStatus");

    char response[2048];
    int len = 0;
    const char* p;

    p = "{\"monitoredContracts\":";
    while (*p) response[len++] = *p++;
    if (g_monitored_count >= 10) response[len++] = '0' + (g_monitored_count / 10);
    response[len++] = '0' + (g_monitored_count % 10);

    p = ",\"detectedChanges\":";
    while (*p) response[len++] = *p++;
    if (g_detected_changes >= 10) response[len++] = '0' + (g_detected_changes / 10);
    response[len++] = '0' + (g_detected_changes % 10);

    p = ",\"lastHeartbeat\":";
    while (*p) response[len++] = *p++;
    /* Format timestamp as decimal */
    int64_t ts = g_last_monitor_heartbeat;
    char ts_buf[20];
    int ts_len = 0;
    if (ts == 0) {
        ts_buf[ts_len++] = '0';
    } else {
        int64_t temp = ts;
        while (temp > 0) {
            ts_buf[ts_len++] = '0' + (temp % 10);
            temp /= 10;
        }
    }
    for (int i = ts_len - 1; i >= 0; i--) {
        response[len++] = ts_buf[i];
    }

    p = ",\"contracts\":[";
    while (*p) response[len++] = *p++;

    for (int32_t i = 0; i < g_monitored_count && len < 1900; i++) {
        if (i > 0) response[len++] = ',';
        response[len++] = '{';

        p = "\"dictionary\":\"";
        while (*p) response[len++] = *p++;
        for (int j = 0; g_monitored_contracts[i].dictionary[j] && j < 42; j++) {
            response[len++] = g_monitored_contracts[i].dictionary[j];
        }
        response[len++] = '"';

        p = ",\"chainId\":";
        while (*p) response[len++] = *p++;
        int32_t cid = g_monitored_contracts[i].chain_id;
        if (cid >= 10000) response[len++] = '0' + (cid / 10000) % 10;
        if (cid >= 1000) response[len++] = '0' + (cid / 1000) % 10;
        if (cid >= 100) response[len++] = '0' + (cid / 100) % 10;
        if (cid >= 10) response[len++] = '0' + (cid / 10) % 10;
        response[len++] = '0' + (cid % 10);

        p = ",\"selectors\":";
        while (*p) response[len++] = *p++;
        response[len++] = '0' + g_monitored_contracts[i].selector_count;

        response[len++] = '}';
    }

    p = "]}";
    while (*p) response[len++] = *p++;
    response[len] = '\0';

    reply_candid_text(response);
}

/*
 * Build batch JSON-RPC request for multiple getImplementation calls
 *
 * This reduces cycles consumption by making a single HTTP request
 * instead of multiple individual requests.
 *
 * Format:
 * [
 *   {"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x...","data":"0xdc9cc645..."},"latest"],"id":1},
 *   {"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x...","data":"0xdc9cc645..."},"latest"],"id":2},
 *   ...
 * ]
 */
static int32_t build_batch_query_json(char* buf, int32_t contract_idx) {
    MonitoredContract* mc = &g_monitored_contracts[contract_idx];
    int32_t len = 0;
    const char* p;

    buf[len++] = '[';

    for (int32_t i = 0; i < mc->selector_count; i++) {
        if (i > 0) buf[len++] = ',';

        /* {"jsonrpc":"2.0","method":"eth_call","params":[{"to":" */
        p = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"";
        while (*p) buf[len++] = *p++;

        /* Dictionary address */
        for (int j = 0; mc->dictionary[j] && j < 42; j++) {
            buf[len++] = mc->dictionary[j];
        }

        /* ","data":"0xdc9cc645 (getImplementation selector) */
        p = "\",\"data\":\"0xdc9cc645";
        while (*p) buf[len++] = *p++;

        /* Append the function selector (right-padded to 32 bytes) */
        /* mc->selectors[i] is like "0xabcdef12", we need just "abcdef12" */
        int sel_start = 0;
        if (mc->selectors[i][0] == '0' && mc->selectors[i][1] == 'x') {
            sel_start = 2;
        }
        for (int j = sel_start; mc->selectors[i][j] && j < 10; j++) {
            buf[len++] = mc->selectors[i][j];
        }
        /* Pad to 32 bytes (64 hex chars - 8 selector hex = 56 zeros) */
        for (int j = 0; j < 56; j++) {
            buf[len++] = '0';
        }

        /* "},"latest"],"id": */
        p = "\"},\"latest\"],\"id\":";
        while (*p) buf[len++] = *p++;

        /* ID (1-based) */
        int id = i + 1;
        if (id >= 10) buf[len++] = '0' + (id / 10);
        buf[len++] = '0' + (id % 10);

        buf[len++] = '}';
    }

    buf[len++] = ']';
    buf[len] = '\0';
    return len;
}

/* Store batch query context */
static int32_t g_batch_contract_idx = -1;

/* Callback for batch query response */
__attribute__((used, visibility("default"), export_name("batch_query_reply_callback")))
void batch_query_reply_callback(int32_t env) {
    (void)env;
    debug("OUC: batch_query_reply_callback");

    /* Read response Candid */
    int32_t arg_size = ic0_msg_arg_data_size();
    static uint8_t response_buf[8192];
    if (arg_size > (int32_t)sizeof(response_buf)) arg_size = sizeof(response_buf);
    if (arg_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)response_buf, 0, arg_size);
    }

    /* EVM RPC returns Candid: variant { Ok : text; Err : ... }
     * Find the JSON text value inside Candid response */
    int32_t json_start = -1;
    int32_t json_end = -1;

    /* Look for JSON start pattern {"jsonrpc" within Candid payload */
    for (int32_t i = 4; i < arg_size - 10; i++) {
        if (response_buf[i] == '{' && response_buf[i+1] == '"' &&
            response_buf[i+2] == 'j' && response_buf[i+3] == 's' &&
            response_buf[i+4] == 'o' && response_buf[i+5] == 'n') {
            json_start = i;
            /* Find end of JSON by matching braces */
            int depth = 1;
            for (int32_t k = i + 1; k < arg_size && depth > 0; k++) {
                if (response_buf[k] == '{') depth++;
                else if (response_buf[k] == '}') depth--;
                if (depth == 0) json_end = k + 1;
            }
            break;
        }
    }

    /* Parse JSON-RPC response - look for "result" fields */
    char result[2048];
    int len = 0;
    const char* p = "{\"batchResults\":[";
    while (*p) result[len++] = *p++;

    int result_count = 0;

    /* Search within extracted JSON */
    int32_t search_start = (json_start >= 0) ? json_start : 10;
    int32_t search_end = (json_end > 0) ? json_end : arg_size;

    for (int32_t i = search_start; i < search_end - 10 && len < 1900; i++) {
        if (response_buf[i] == '"' && response_buf[i+1] == 'r' &&
            response_buf[i+2] == 'e' && response_buf[i+3] == 's' &&
            response_buf[i+4] == 'u' && response_buf[i+5] == 'l' &&
            response_buf[i+6] == 't' && response_buf[i+7] == '"') {
            /* Found "result", extract the value */
            int32_t j = i + 8;
            /* Skip : and whitespace */
            while (j < arg_size && (response_buf[j] == ':' || response_buf[j] == ' ')) j++;

            if (response_buf[j] == '"') {
                /* String result */
                j++; /* Skip opening quote */
                if (result_count > 0) result[len++] = ',';
                result[len++] = '"';
                while (j < arg_size && response_buf[j] != '"' && len < 1950) {
                    result[len++] = (char)response_buf[j++];
                }
                result[len++] = '"';
                result_count++;
            }
        }
    }

    p = "],\"count\":";
    while (*p) result[len++] = *p++;
    if (result_count >= 10) result[len++] = '0' + (result_count / 10);
    result[len++] = '0' + (result_count % 10);

    /* Update monitoring state if we have a valid contract index */
    if (g_batch_contract_idx >= 0 && g_batch_contract_idx < g_monitored_count) {
        MonitoredContract* mc = &g_monitored_contracts[g_batch_contract_idx];
        /* Note: Full implementation would parse each result and compare with stored implementations */
        /* For now, just update the timestamp */
        /* mc->last_checked = current_time; */
    }

    p = ",\"contractIdx\":";
    while (*p) result[len++] = *p++;
    if (g_batch_contract_idx >= 10) result[len++] = '0' + (g_batch_contract_idx / 10);
    result[len++] = '0' + (g_batch_contract_idx % 10);

    result[len++] = '}';
    result[len] = '\0';

    g_batch_contract_idx = -1;  /* Reset */
    reply_candid_text(result);
}

/* Callback for batch query rejection */
__attribute__((used, visibility("default"), export_name("batch_query_reject_callback")))
void batch_query_reject_callback(int32_t env) {
    (void)env;
    debug("OUC: batch_query_reject_callback");

    int32_t reject_code = ic0_msg_reject_code();
    char response[256];
    int32_t len = 0;
    const char* p = "{\"error\":\"batch_query_rejected\",\"code\":";
    while (*p) response[len++] = *p++;
    if (reject_code >= 10) response[len++] = '0' + (reject_code / 10);
    response[len++] = '0' + (reject_code % 10);
    response[len++] = '}';
    response[len] = '\0';

    g_batch_contract_idx = -1;
    reply_candid_text(response);
}

/*
 * Poll a monitored contract using batch JSON-RPC
 *
 * Arguments: (contractIndex : nat32) -> (text)
 * Returns: batch results for all selectors
 */
__attribute__((used, visibility("default"), export_name("canister_update pollContract")))
void canister_update_pollContract(void) {
    debug("OUC: pollContract - batch query");

    load_candid_args();

    /* Parse contract index from Candid (nat32) */
    int32_t contract_idx = 0;
    if (arg_buf_size >= 12) {
        /* Skip DIDL header + type info */
        int32_t offset = 4;
        int32_t new_offset;
        uint64_t type_count = parse_leb128(offset, &new_offset);
        offset = new_offset;
        for (uint64_t i = 0; i < type_count; i++) {
            parse_leb128(offset, &new_offset);
            offset = new_offset;
        }
        parse_leb128(offset, &new_offset);  /* arg count */
        offset = new_offset + 1;  /* skip type code */

        if (offset + 4 <= arg_buf_size) {
            contract_idx = arg_buf[offset] | (arg_buf[offset+1] << 8) |
                          (arg_buf[offset+2] << 16) | (arg_buf[offset+3] << 24);
        }
    }

    if (contract_idx < 0 || contract_idx >= g_monitored_count) {
        reply_candid_text("{\"error\":\"invalid_contract_index\"}");
        return;
    }

    MonitoredContract* mc = &g_monitored_contracts[contract_idx];
    if (mc->selector_count == 0) {
        reply_candid_text("{\"error\":\"no_selectors\"}");
        return;
    }

    /* Build single eth_call JSON-RPC request for first selector
     * Note: EVM RPC canister doesn't support JSON-RPC batch requests directly.
     * For true batch optimization, would need to use Multicall contract on-chain.
     * This implementation queries the first selector as a working demonstration.
     */
    static char json_buf[512];
    int32_t jlen = 0;
    const char* p;

    p = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"";
    while (*p) json_buf[jlen++] = *p++;
    for (int j = 0; mc->dictionary[j] && j < 42; j++) {
        json_buf[jlen++] = mc->dictionary[j];
    }
    p = "\",\"data\":\"0xdc9cc645";  /* getImplementation(bytes4) for ERC-7546 */
    while (*p) json_buf[jlen++] = *p++;
    /* Append selector (skip 0x prefix if present) */
    int sel_start = (mc->selectors[0][0] == '0' && mc->selectors[0][1] == 'x') ? 2 : 0;
    for (int j = sel_start; mc->selectors[0][j] && j < 10; j++) {
        json_buf[jlen++] = mc->selectors[0][j];
    }
    /* Pad to 32 bytes (56 zeros) */
    for (int j = 0; j < 56; j++) json_buf[jlen++] = '0';
    p = "\"},\"latest\"],\"id\":1}";
    while (*p) json_buf[jlen++] = *p++;
    json_buf[jlen] = '\0';

    /* Build Candid for EVM RPC request using Idris2 (type-safe) */
    int32_t candid_len = encode_evm_rpc_idris2(json_buf, mc->chain_id, 2000);
    if (candid_len < 0) {
        debug("OUC: Unknown chain_id for Candid encoding");
        return;
    }
    uint8_t* candid_buf = ouc_c_get_candid_buf();

    /* Store context for callback */
    g_batch_contract_idx = contract_idx;

    /* Setup call to EVM RPC canister */
    const char* method = "request";

    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = batch_query_reply_callback;
    callback_fn reject_cb = batch_query_reject_callback;

    /* ic0.call_new signature: callee, callee_size, method, method_size,
     *                         reply_fun, reply_env, reject_fun, reject_env */
    ic0_call_new(
        (int32_t)(uintptr_t)EVM_RPC_CANISTER_ID, EVM_RPC_CANISTER_ID_LEN,
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),
        (int32_t)(uintptr_t)reply_cb,
        0,
        (int32_t)(uintptr_t)reject_cb,
        0
    );

    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);
    ic0_call_cycles_add128(0, 1000000000);  /* 1B cycles */

    int32_t result = ic0_call_perform();
    if (result != 0) {
        char err[64];
        int len = 0;
        const char* p = "{\"error\":\"call_failed\",\"code\":";
        while (*p) err[len++] = *p++;
        err[len++] = '0' + (result % 10);
        err[len++] = '}';
        err[len] = '\0';
        g_batch_contract_idx = -1;
        reply_candid_text(err);
    }
}

/* =============================================================================
 * EVM Event Fetching (eth_getLogs)
 * ============================================================================= */

/* Context for eth_getLogs callback */
static uint64_t g_fetch_from_block = 0;
static uint64_t g_fetch_to_block = 0;
static char g_fetch_address[44] = {0};  /* Contract address to filter */

/*
 * Build eth_getLogs JSON-RPC request
 */
static int32_t build_eth_get_logs_json(char* buf, uint64_t from_block, uint64_t to_block,
                                        const char* address) {
    int32_t len = 0;
    const char* p;

    p = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{";
    while (*p) buf[len++] = *p++;

    /* fromBlock */
    p = "\"fromBlock\":\"0x";
    while (*p) buf[len++] = *p++;
    /* Convert to hex */
    char hex[20];
    int hlen = 0;
    uint64_t n = from_block;
    if (n == 0) {
        hex[hlen++] = '0';
    } else {
        while (n > 0) {
            int d = n & 0xF;
            hex[hlen++] = (d < 10) ? ('0' + d) : ('a' + d - 10);
            n >>= 4;
        }
    }
    for (int i = hlen - 1; i >= 0; i--) buf[len++] = hex[i];

    /* toBlock */
    p = "\",\"toBlock\":\"0x";
    while (*p) buf[len++] = *p++;
    hlen = 0;
    n = to_block;
    if (n == 0) {
        hex[hlen++] = '0';
    } else {
        while (n > 0) {
            int d = n & 0xF;
            hex[hlen++] = (d < 10) ? ('0' + d) : ('a' + d - 10);
            n >>= 4;
        }
    }
    for (int i = hlen - 1; i >= 0; i--) buf[len++] = hex[i];
    buf[len++] = '"';

    /* address filter (optional) */
    if (address && address[0]) {
        p = ",\"address\":\"";
        while (*p) buf[len++] = *p++;
        for (int i = 0; address[i] && i < 42; i++) {
            buf[len++] = address[i];
        }
        buf[len++] = '"';
    }

    p = "}],\"id\":1}";
    while (*p) buf[len++] = *p++;
    buf[len] = '\0';

    return len;
}

/* Parse hex string to uint64 */
static uint64_t parse_hex_uint64(const char* hex, int len) {
    uint64_t result = 0;
    int start = 0;
    if (len >= 2 && hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        start = 2;
    }
    for (int i = start; i < len; i++) {
        char c = hex[i];
        int d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = 10 + c - 'a';
        else if (c >= 'A' && c <= 'F') d = 10 + c - 'A';
        else break;
        result = (result << 4) | d;
    }
    return result;
}

/* Parse a single log entry from JSON and store to SQLite via Idris2
 * Returns: 1 if parsed successfully, 0 otherwise
 *
 * Expected log format:
 * {"address":"0x...","topics":["0x...","0x..."...],"data":"0x...","blockNumber":"0x...","transactionHash":"0x...","logIndex":"0x..."}
 */
static int32_t parse_and_store_log(const char* log_start, int32_t log_len) {
    /* Find key fields - simplified JSON parser */
    const char* address = NULL;
    int address_len = 0;
    const char* topic0 = NULL;
    int topic0_len = 0;
    const char* block_num = NULL;
    int block_num_len = 0;
    const char* tx_hash = NULL;
    int tx_hash_len = 0;

    /* Search for "address":" */
    for (int i = 0; i < log_len - 12; i++) {
        if (log_start[i] == 'a' && log_start[i+1] == 'd' && log_start[i+2] == 'd' &&
            log_start[i+3] == 'r' && log_start[i+4] == 'e' && log_start[i+5] == 's' &&
            log_start[i+6] == 's' && log_start[i+7] == '"' && log_start[i+8] == ':' &&
            log_start[i+9] == '"') {
            address = &log_start[i+10];
            for (int j = 0; i+10+j < log_len && log_start[i+10+j] != '"'; j++) {
                address_len++;
            }
            break;
        }
    }

    /* Search for "topics":["0x... */
    for (int i = 0; i < log_len - 12; i++) {
        if (log_start[i] == 't' && log_start[i+1] == 'o' && log_start[i+2] == 'p' &&
            log_start[i+3] == 'i' && log_start[i+4] == 'c' && log_start[i+5] == 's' &&
            log_start[i+6] == '"' && log_start[i+7] == ':' && log_start[i+8] == '[' &&
            log_start[i+9] == '"') {
            topic0 = &log_start[i+10];
            for (int j = 0; i+10+j < log_len && log_start[i+10+j] != '"'; j++) {
                topic0_len++;
            }
            break;
        }
    }

    /* Search for "blockNumber":" */
    for (int i = 0; i < log_len - 15; i++) {
        if (log_start[i] == 'b' && log_start[i+1] == 'l' && log_start[i+2] == 'o' &&
            log_start[i+3] == 'c' && log_start[i+4] == 'k' && log_start[i+5] == 'N' &&
            log_start[i+6] == 'u' && log_start[i+7] == 'm' && log_start[i+8] == 'b' &&
            log_start[i+9] == 'e' && log_start[i+10] == 'r' && log_start[i+11] == '"' &&
            log_start[i+12] == ':' && log_start[i+13] == '"') {
            block_num = &log_start[i+14];
            for (int j = 0; i+14+j < log_len && log_start[i+14+j] != '"'; j++) {
                block_num_len++;
            }
            break;
        }
    }

    if (!address || !block_num) {
        return 0;  /* Required fields missing */
    }

    /* Parse block number */
    uint64_t block = parse_hex_uint64(block_num, block_num_len);

    /* Store event via Idris2 (CMD_STORE_TEST_EVENT with parsed data)
     * For now, use simple storage - real impl would pass full event data */
    int32_t event_type = 0;  /* UpgradeProposed by default */
    if (topic0 && topic0_len >= 10) {
        /* Detect event type from topic0 prefix */
        /* VoteCast: 0x8c0e... */
        if (topic0[2] == '8' && topic0[3] == 'c') event_type = 1;
        /* ProposalExecuted: 0x41c... */
        else if (topic0[2] == '4' && topic0[3] == '1') event_type = 2;
    }

    /* Call Idris2 to store event */
    call_idris2_2arg(CMD_STORE_TEST_EVENT, (int32_t)block, event_type);

    return 1;
}

/* Parse eth_getLogs response and store events */
static int32_t parse_and_store_logs(const char* json, int32_t len) {
    int32_t events_stored = 0;

    /* Find "result":[ array start */
    int result_start = -1;
    for (int i = 0; i < len - 10; i++) {
        if (json[i] == '"' && json[i+1] == 'r' && json[i+2] == 'e' &&
            json[i+3] == 's' && json[i+4] == 'u' && json[i+5] == 'l' &&
            json[i+6] == 't' && json[i+7] == '"' && json[i+8] == ':' &&
            json[i+9] == '[') {
            result_start = i + 10;
            break;
        }
    }

    if (result_start < 0) {
        return 0;  /* No result array found */
    }

    /* Parse each log object in the array */
    int brace_count = 0;
    int log_start = -1;

    for (int i = result_start; i < len; i++) {
        if (json[i] == '{') {
            if (brace_count == 0) {
                log_start = i;
            }
            brace_count++;
        } else if (json[i] == '}') {
            brace_count--;
            if (brace_count == 0 && log_start >= 0) {
                /* Found complete log object */
                int log_len = i - log_start + 1;
                if (parse_and_store_log(&json[log_start], log_len)) {
                    events_stored++;
                }
                log_start = -1;
            }
        } else if (json[i] == ']' && brace_count == 0) {
            break;  /* End of result array */
        }
    }

    return events_stored;
}

/* Callback for eth_getLogs response */
__attribute__((used, visibility("default"), export_name("fetch_logs_reply_callback")))
void fetch_logs_reply_callback(int32_t env) {
    (void)env;
    debug("OUC: fetch_logs_reply_callback");

    /* Read response Candid */
    int32_t arg_size = ic0_msg_arg_data_size();
    static uint8_t response_buf[8192];
    if (arg_size > (int32_t)sizeof(response_buf)) arg_size = sizeof(response_buf);
    if (arg_size > 0) {
        ic0_msg_arg_data_copy((int32_t)(uintptr_t)response_buf, 0, arg_size);
    }

    /* Find JSON in response */
    char result[1024];
    int len = 0;
    int32_t events_stored = 0;

    for (int32_t i = 10; i < arg_size - 10; i++) {
        if (response_buf[i] == '{' && response_buf[i+1] == '"') {
            /* Found JSON start - extract and parse logs */
            int brace_count = 0;
            int json_start = i;
            int json_end = i;

            for (int32_t j = i; j < arg_size; j++) {
                if (response_buf[j] == '{') brace_count++;
                if (response_buf[j] == '}') {
                    brace_count--;
                    if (brace_count == 0) {
                        json_end = j;
                        break;
                    }
                }
            }

            /* Parse and store logs */
            events_stored = parse_and_store_logs((const char*)&response_buf[json_start],
                                                  json_end - json_start + 1);
            break;
        }
    }

    /* Build response */
    const char* prefix = "{\"fromBlock\":";
    const char* p = prefix;
    while (*p) result[len++] = *p++;

    /* Add from block */
    char num[20];
    int nlen = 0;
    uint64_t n = g_fetch_from_block;
    if (n == 0) num[nlen++] = '0';
    else {
        while (n > 0) { num[nlen++] = '0' + (n % 10); n /= 10; }
    }
    for (int i = nlen - 1; i >= 0; i--) result[len++] = num[i];

    p = ",\"toBlock\":";
    while (*p) result[len++] = *p++;
    nlen = 0;
    n = g_fetch_to_block;
    if (n == 0) num[nlen++] = '0';
    else {
        while (n > 0) { num[nlen++] = '0' + (n % 10); n /= 10; }
    }
    for (int i = nlen - 1; i >= 0; i--) result[len++] = num[i];

    p = ",\"eventsStored\":";
    while (*p) result[len++] = *p++;
    nlen = 0;
    n = events_stored;
    if (n == 0) num[nlen++] = '0';
    else {
        while (n > 0) { num[nlen++] = '0' + (n % 10); n /= 10; }
    }
    for (int i = nlen - 1; i >= 0; i--) result[len++] = num[i];

    result[len++] = '}';
    result[len] = '\0';

    reply_candid_text(result);
}

/* Callback for eth_getLogs rejection */
__attribute__((used, visibility("default"), export_name("fetch_logs_reject_callback")))
void fetch_logs_reject_callback(int32_t env) {
    (void)env;
    debug("OUC: fetch_logs_reject_callback");

    int32_t reject_code = ic0_msg_reject_code();
    char response[256];
    int32_t len = 0;
    const char* p = "{\"error\":\"fetch_logs_rejected\",\"code\":";
    while (*p) response[len++] = *p++;
    if (reject_code >= 10) response[len++] = '0' + (reject_code / 10);
    response[len++] = '0' + (reject_code % 10);
    response[len++] = '}';
    response[len] = '\0';

    reply_candid_text(response);
}

/*
 * Fetch EVM logs for a block range
 *
 * Arguments (Candid): (fromBlock : nat64, toBlock : nat64, address : opt text) -> (text)
 * Returns JSON: {"fromBlock":N,"toBlock":M,"eventsStored":K}
 */
__attribute__((used, visibility("default"), export_name("canister_update fetchEvmLogs")))
void canister_update_fetchEvmLogs(void) {
    debug("OUC: fetchEvmLogs");

    load_candid_args();

    /* Parse arguments: (nat64, nat64, opt text) */
    /* Skip DIDL header and type table */
    int32_t offset = 4;
    int32_t new_offset;

    uint64_t type_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    for (uint64_t i = 0; i < type_count; i++) {
        parse_leb128(offset, &new_offset);
        offset = new_offset;
    }

    /* Parse arg count */
    uint64_t arg_count = parse_leb128(offset, &new_offset);
    offset = new_offset;
    if (arg_count < 2) {
        reply_candid_text("{\"error\":\"need_at_least_2_args\"}");
        return;
    }

    /* Skip type codes */
    offset += (int32_t)arg_count;

    /* Parse fromBlock (nat64 = 8 bytes little-endian) */
    if (offset + 8 > arg_buf_size) {
        reply_candid_text("{\"error\":\"invalid_fromBlock\"}");
        return;
    }
    g_fetch_from_block = 0;
    for (int i = 0; i < 8; i++) {
        g_fetch_from_block |= ((uint64_t)arg_buf[offset + i]) << (i * 8);
    }
    offset += 8;

    /* Parse toBlock (nat64 = 8 bytes little-endian) */
    if (offset + 8 > arg_buf_size) {
        reply_candid_text("{\"error\":\"invalid_toBlock\"}");
        return;
    }
    g_fetch_to_block = 0;
    for (int i = 0; i < 8; i++) {
        g_fetch_to_block |= ((uint64_t)arg_buf[offset + i]) << (i * 8);
    }
    offset += 8;

    /* Parse optional address (opt text) */
    g_fetch_address[0] = '\0';
    if (offset < arg_buf_size) {
        uint8_t opt_tag = arg_buf[offset++];
        if (opt_tag == 1 && offset < arg_buf_size) {
            /* Some - parse text length and content */
            uint64_t text_len = parse_leb128(offset, &new_offset);
            offset = new_offset;
            if (text_len > 0 && text_len < 43 && offset + text_len <= arg_buf_size) {
                for (uint64_t i = 0; i < text_len; i++) {
                    g_fetch_address[i] = (char)arg_buf[offset + i];
                }
                g_fetch_address[text_len] = '\0';
            }
        }
    }

    /* Build eth_getLogs JSON-RPC */
    static char json_buf[512];
    build_eth_get_logs_json(json_buf, g_fetch_from_block, g_fetch_to_block,
                            g_fetch_address[0] ? g_fetch_address : NULL);

    /* Build Candid for EVM RPC request using Idris2 */
    int32_t candid_len = encode_evm_rpc_idris2(json_buf, 1 /* EthMainnet */, 8000);
    if (candid_len < 0) {
        reply_candid_text("{\"error\":\"candid_encoding_failed\"}");
        return;
    }
    uint8_t* candid_buf = ouc_c_get_candid_buf();

    /* Setup call to EVM RPC canister */
    const char* method = "request";

    typedef void (*callback_fn)(int32_t);
    callback_fn reply_cb = fetch_logs_reply_callback;
    callback_fn reject_cb = fetch_logs_reject_callback;

    ic0_call_new(
        (int32_t)(uintptr_t)EVM_RPC_CANISTER_ID, EVM_RPC_CANISTER_ID_LEN,
        (int32_t)(uintptr_t)method, (int32_t)strlen(method),
        (int32_t)(uintptr_t)reply_cb, 0,
        (int32_t)(uintptr_t)reject_cb, 0
    );

    ic0_call_data_append((int32_t)(uintptr_t)candid_buf, candid_len);
    ic0_call_cycles_add128(0, 20000000000ULL);  /* 20B cycles for larger response */

    int32_t result = ic0_call_perform();
    if (result != 0) {
        char err[64];
        int len = 0;
        const char* p = "{\"error\":\"call_failed\",\"code\":";
        while (*p) err[len++] = *p++;
        err[len++] = '0' + (result % 10);
        err[len++] = '}';
        err[len] = '\0';
        reply_candid_text(err);
    }
}
