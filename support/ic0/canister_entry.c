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
extern uint64_t ic0_time(void);
extern void ic0_debug_print(int32_t src, int32_t size);
extern void ic0_trap(int32_t src, int32_t size);

/* Forward declarations from Idris2 generated code */
extern void* __mainExpression_0(void);  /* Idris2 main entry - returns IO closure */
extern void* idris2_trampoline(void*);  /* Execute Idris2 closure (from RefC runtime) */

/* Forward declarations from ic0_stubs.c (FFI bridge) */
extern void ouc_c_set_arg_i32(int32_t index, int32_t value);
extern int32_t ouc_c_get_result_i32(void);
extern void ouc_reset_ffi(void);
extern int64_t ouc_get_auditor_count(void);  /* Direct access for debugging */

/* Command constants (must match Main.idr) */
/* Query commands (0-9) */
#define CMD_INIT               0
#define CMD_GET_VERSION        1
#define CMD_GET_PROPOSAL_COUNT 2
#define CMD_GET_AUDITOR_COUNT  3
/* Update commands (10+) */
#define CMD_REGISTER_AUDITOR   10
#define CMD_SUSPEND_AUDITOR    11
#define CMD_REACTIVATE_AUDITOR 12

/* Call Idris2 with a command and return the result */
static int32_t call_idris2(int32_t cmd) {
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, cmd);
    /* __mainExpression_0 returns an IO closure, idris2_trampoline executes it */
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);
    return ouc_c_get_result_i32();
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
    /* LEB128 length (simplified: assuming len < 128) */
    uint8_t leb_len = (uint8_t)len;
    ic0_msg_reply_data_append((int32_t)(uintptr_t)&leb_len, 1);
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
    /* TODO: Serialize OUCState to stable memory */
}

__attribute__((used, visibility("default"), export_name("canister_post_upgrade")))
void canister_post_upgrade(void) {
    debug("OUC: canister_post_upgrade");
    /* Re-initialize state using CMD_INIT
     * TODO: Deserialize OUCState from stable memory instead of reinitializing */
    int32_t result = call_idris2(CMD_INIT);
    if (result == 1) {
        debug("OUC: post_upgrade initialized state");
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
    /* TODO: Parse ProposalId from args, call findProposal, encode FR response */
    reply_candid_text("getProposal: not yet implemented");
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
    int32_t count = call_idris2(CMD_GET_PROPOSAL_COUNT);
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
    /* TODO: Parse args, call submitProposal, encode FR response */
    reply_candid_text("submitProposal: not yet implemented");
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
