/*
 * SQLite Bridge for IC Canisters
 *
 * Implementation of minimal SQLite interface.
 *
 * IMPORTANT: This file requires sqlite3.c (amalgamation) to be present.
 * Download from: https://sqlite.org/download.html (sqlite-amalgamation-*.zip)
 * Place sqlite3.c and sqlite3.h in lib/ic0/sqlite/
 *
 * Build command (add to Emscripten compile):
 *   -I lib/ic0/sqlite
 *   -DSQLITE_THREADSAFE=0
 *   -DSQLITE_OMIT_LOAD_EXTENSION
 *   -DSQLITE_OMIT_DEPRECATED
 *   -DSQLITE_OMIT_PROGRESS_CALLBACK
 *   -DSQLITE_OMIT_SHARED_CACHE
 *   -DSQLITE_DEFAULT_MEMSTATUS=0
 *   -DSQLITE_DQS=0
 *   -DSQLITE_ENABLE_DESERIALIZE
 */

#include "sqlite_bridge.h"
#include <string.h>

/*
 * Conditional SQLite include - allows building without SQLite for testing
 * When SQLITE_BRIDGE_STUB is defined, use stub implementations
 */
#ifdef SQLITE_BRIDGE_STUB

/* =============================================================================
 * Stub Implementation (for testing without SQLite)
 * ============================================================================= */

static int stub_is_open = 0;
static char stub_errmsg[256] = "";

int sql_open(void) {
    stub_is_open = 1;
    return 0;
}

int sql_close(void) {
    stub_is_open = 0;
    return 0;
}

int sql_is_open(void) {
    return stub_is_open;
}

int sql_exec(const char* sql) {
    (void)sql;
    return 0;
}

const char* sql_errmsg(void) {
    return stub_errmsg;
}

int sql_changes(void) { return 0; }
int64_t sql_last_insert_rowid(void) { return 0; }

int sql_prepare(const char* sql) { (void)sql; return 0; }
int sql_step(void) { return 101; }  /* SQLITE_DONE */
int sql_reset(void) { return 0; }
int sql_finalize(void) { return 0; }
int sql_column_count(void) { return 0; }

int sql_bind_null(int idx) { (void)idx; return 0; }
int sql_bind_int(int idx, int64_t val) { (void)idx; (void)val; return 0; }
int sql_bind_text(int idx, const char* val, int len) { (void)idx; (void)val; (void)len; return 0; }
int sql_bind_blob(int idx, const void* val, int len) { (void)idx; (void)val; (void)len; return 0; }

int sql_column_type(int idx) { (void)idx; return 5; }  /* NULL */
int64_t sql_column_int(int idx) { (void)idx; return 0; }
const char* sql_column_text(int idx) { (void)idx; return ""; }
int sql_column_bytes(int idx) { (void)idx; return 0; }
const void* sql_column_blob(int idx) { (void)idx; return NULL; }

int64_t sql_serialize_size(void) { return 0; }
int64_t sql_serialize(uint8_t* buf, int64_t max_len) { (void)buf; (void)max_len; return 0; }
int sql_deserialize(const uint8_t* buf, int64_t len) { (void)buf; (void)len; return 0; }

#else /* Real SQLite implementation */

#include "sqlite3.h"

/* =============================================================================
 * Global State
 * ============================================================================= */

static sqlite3* g_db = NULL;
static sqlite3_stmt* g_stmt = NULL;

/* =============================================================================
 * Database Lifecycle
 * ============================================================================= */

int sql_open(void) {
    if (g_db != NULL) {
        return 0;  /* Already open */
    }
    int rc = sqlite3_open(":memory:", &g_db);
    if (rc != SQLITE_OK) {
        g_db = NULL;
    }
    return rc;
}

int sql_close(void) {
    if (g_stmt != NULL) {
        sqlite3_finalize(g_stmt);
        g_stmt = NULL;
    }
    if (g_db != NULL) {
        int rc = sqlite3_close(g_db);
        g_db = NULL;
        return rc;
    }
    return 0;
}

int sql_is_open(void) {
    return g_db != NULL ? 1 : 0;
}

/* =============================================================================
 * SQL Execution
 * ============================================================================= */

int sql_exec(const char* sql) {
    if (g_db == NULL) return 1;  /* SQLITE_ERROR */
    char* errmsg = NULL;
    int rc = sqlite3_exec(g_db, sql, NULL, NULL, &errmsg);
    if (errmsg) sqlite3_free(errmsg);
    return rc;
}

const char* sql_errmsg(void) {
    if (g_db == NULL) return "Database not open";
    return sqlite3_errmsg(g_db);
}

int sql_changes(void) {
    if (g_db == NULL) return 0;
    return sqlite3_changes(g_db);
}

int64_t sql_last_insert_rowid(void) {
    if (g_db == NULL) return 0;
    return sqlite3_last_insert_rowid(g_db);
}

/* =============================================================================
 * Prepared Statement API
 * ============================================================================= */

int sql_prepare(const char* sql) {
    if (g_db == NULL) return 1;
    if (g_stmt != NULL) {
        sqlite3_finalize(g_stmt);
        g_stmt = NULL;
    }
    return sqlite3_prepare_v2(g_db, sql, -1, &g_stmt, NULL);
}

int sql_step(void) {
    if (g_stmt == NULL) return 1;
    return sqlite3_step(g_stmt);
}

int sql_reset(void) {
    if (g_stmt == NULL) return 1;
    return sqlite3_reset(g_stmt);
}

int sql_finalize(void) {
    if (g_stmt == NULL) return 0;
    int rc = sqlite3_finalize(g_stmt);
    g_stmt = NULL;
    return rc;
}

int sql_column_count(void) {
    if (g_stmt == NULL) return 0;
    return sqlite3_column_count(g_stmt);
}

/* =============================================================================
 * Parameter Binding
 * ============================================================================= */

int sql_bind_null(int idx) {
    if (g_stmt == NULL) return 1;
    return sqlite3_bind_null(g_stmt, idx);
}

int sql_bind_int(int idx, int64_t val) {
    if (g_stmt == NULL) return 1;
    return sqlite3_bind_int64(g_stmt, idx, val);
}

int sql_bind_text(int idx, const char* val, int len) {
    if (g_stmt == NULL) return 1;
    return sqlite3_bind_text(g_stmt, idx, val, len, SQLITE_TRANSIENT);
}

int sql_bind_blob(int idx, const void* val, int len) {
    if (g_stmt == NULL) return 1;
    return sqlite3_bind_blob(g_stmt, idx, val, len, SQLITE_TRANSIENT);
}

/* =============================================================================
 * Column Accessors
 * ============================================================================= */

int sql_column_type(int idx) {
    if (g_stmt == NULL) return 5;  /* NULL */
    return sqlite3_column_type(g_stmt, idx);
}

int64_t sql_column_int(int idx) {
    if (g_stmt == NULL) return 0;
    return sqlite3_column_int64(g_stmt, idx);
}

const char* sql_column_text(int idx) {
    if (g_stmt == NULL) return "";
    const char* text = (const char*)sqlite3_column_text(g_stmt, idx);
    return text ? text : "";
}

int sql_column_bytes(int idx) {
    if (g_stmt == NULL) return 0;
    return sqlite3_column_bytes(g_stmt, idx);
}

const void* sql_column_blob(int idx) {
    if (g_stmt == NULL) return NULL;
    return sqlite3_column_blob(g_stmt, idx);
}

/* =============================================================================
 * Serialization
 * ============================================================================= */

int64_t sql_serialize_size(void) {
    if (g_db == NULL) return -1;
    sqlite3_int64 size = 0;
    unsigned char* data = sqlite3_serialize(g_db, "main", &size, 0);
    if (data == NULL) return -1;
    sqlite3_free(data);
    return (int64_t)size;
}

int64_t sql_serialize(uint8_t* buf, int64_t max_len) {
    if (g_db == NULL) return -1;
    sqlite3_int64 size = 0;
    unsigned char* data = sqlite3_serialize(g_db, "main", &size, 0);
    if (data == NULL) return -1;

    int64_t copy_len = (size < max_len) ? size : max_len;
    memcpy(buf, data, (size_t)copy_len);
    sqlite3_free(data);
    return copy_len;
}

int sql_deserialize(const uint8_t* buf, int64_t len) {
    /* Close existing database */
    sql_close();

    /* Open new in-memory database */
    int rc = sqlite3_open(":memory:", &g_db);
    if (rc != SQLITE_OK) {
        g_db = NULL;
        return rc;
    }

    /* Allocate buffer for SQLite (it takes ownership) */
    unsigned char* data = sqlite3_malloc64((sqlite3_uint64)len);
    if (data == NULL) {
        sql_close();
        return 7;  /* SQLITE_NOMEM */
    }
    memcpy(data, buf, (size_t)len);

    /* Deserialize into database */
    rc = sqlite3_deserialize(g_db, "main", data, (sqlite3_int64)len,
                              (sqlite3_int64)len, SQLITE_DESERIALIZE_FREEONCLOSE);
    if (rc != SQLITE_OK) {
        sql_close();
    }
    return rc;
}

#endif /* SQLITE_BRIDGE_STUB */

/* =============================================================================
 * String Buffer for Idris FFI
 * ============================================================================= */

static char g_str_buffer[SQL_STRING_BUFFER_SIZE];
static int64_t g_str_len = 0;

void sql_ffi_str_reset(void) {
    g_str_len = 0;
    g_str_buffer[0] = '\0';
}

void sql_ffi_str_push(int64_t byte) {
    if (g_str_len < SQL_STRING_BUFFER_SIZE - 1) {
        g_str_buffer[g_str_len++] = (char)byte;
        g_str_buffer[g_str_len] = '\0';  /* Keep null-terminated */
    }
}

int64_t sql_ffi_str_ptr(void) {
    return (int64_t)(uintptr_t)g_str_buffer;
}

int64_t sql_ffi_str_len(void) {
    return g_str_len;
}

/* =============================================================================
 * Idris FFI Wrappers
 * ============================================================================= */

void sql_ffi_open(void) {
    sql_open();
}

void sql_ffi_close(void) {
    sql_close();
}

int64_t sql_ffi_is_open(void) {
    return (int64_t)sql_is_open();
}

int64_t sql_ffi_exec(int64_t sql_ptr, int64_t sql_len) {
    /* Null-terminate the string */
    char* sql = (char*)(uintptr_t)sql_ptr;
    char saved = sql[sql_len];
    sql[sql_len] = '\0';
    int rc = sql_exec(sql);
    sql[sql_len] = saved;
    return (int64_t)rc;
}

int64_t sql_ffi_prepare(int64_t sql_ptr, int64_t sql_len) {
    char* sql = (char*)(uintptr_t)sql_ptr;
    char saved = sql[sql_len];
    sql[sql_len] = '\0';
    int rc = sql_prepare(sql);
    sql[sql_len] = saved;
    return (int64_t)rc;
}

int64_t sql_ffi_step(void) {
    return (int64_t)sql_step();
}

int64_t sql_ffi_reset(void) {
    return (int64_t)sql_reset();
}

int64_t sql_ffi_finalize(void) {
    return (int64_t)sql_finalize();
}

int64_t sql_ffi_column_count(void) {
    return (int64_t)sql_column_count();
}

int64_t sql_ffi_bind_null(int64_t idx) {
    return (int64_t)sql_bind_null((int)idx);
}

int64_t sql_ffi_bind_int(int64_t idx, int64_t val) {
    return (int64_t)sql_bind_int((int)idx, val);
}

int64_t sql_ffi_bind_text(int64_t idx, int64_t val_ptr, int64_t val_len) {
    return (int64_t)sql_bind_text((int)idx, (const char*)(uintptr_t)val_ptr, (int)val_len);
}

int64_t sql_ffi_bind_blob(int64_t idx, int64_t val_ptr, int64_t val_len) {
    return (int64_t)sql_bind_blob((int)idx, (const void*)(uintptr_t)val_ptr, (int)val_len);
}

int64_t sql_ffi_column_type(int64_t idx) {
    return (int64_t)sql_column_type((int)idx);
}

int64_t sql_ffi_column_int(int64_t idx) {
    return sql_column_int((int)idx);
}

int64_t sql_ffi_column_text_len(int64_t idx) {
    return (int64_t)sql_column_bytes((int)idx);
}

int64_t sql_ffi_column_text_byte(int64_t idx, int64_t byte_idx) {
    const char* text = sql_column_text((int)idx);
    int len = sql_column_bytes((int)idx);
    if (byte_idx >= 0 && byte_idx < len) {
        return (int64_t)(uint8_t)text[byte_idx];
    }
    return 0;
}

int64_t sql_ffi_changes(void) {
    return (int64_t)sql_changes();
}

int64_t sql_ffi_last_insert_rowid(void) {
    return sql_last_insert_rowid();
}

int64_t sql_ffi_serialize_size(void) {
    return sql_serialize_size();
}

int64_t sql_ffi_serialize(int64_t buf_ptr, int64_t max_len) {
    return sql_serialize((uint8_t*)(uintptr_t)buf_ptr, max_len);
}

int64_t sql_ffi_deserialize(int64_t buf_ptr, int64_t len) {
    return (int64_t)sql_deserialize((const uint8_t*)(uintptr_t)buf_ptr, len);
}
