/*
 * Stable B+Tree Implementation for ICP Canisters
 *
 * O(log n) key-value storage backed by stable memory.
 *
 * Design:
 * - B+Tree with configurable order
 * - All values stored in leaf nodes
 * - Leaf nodes linked for range queries
 * - Fixed 4KB pages for cache efficiency
 *
 * Memory Layout:
 *   Page 0: Header
 *     [0..3]   : Magic "STBT"
 *     [4..7]   : Root page number
 *     [8..11]  : Total page count
 *     [12..15] : Entry count
 *     [16..19] : Tree height
 *     [20..4095] : Reserved
 *
 *   Page N (Internal Node):
 *     [0]      : Node type (0 = internal)
 *     [1..2]   : Key count
 *     [3..4]   : Reserved
 *     [5..]    : [child0][key0][child1][key1]...[childN]
 *                Each child: 4 bytes (page number)
 *                Each key: [len:2][data:len]
 *
 *   Page N (Leaf Node):
 *     [0]      : Node type (1 = leaf)
 *     [1..2]   : Entry count
 *     [3..6]   : Next leaf page (0 = none)
 *     [7..10]  : Prev leaf page (0 = none)
 *     [11..]   : [key_len:2][key][val_len:2][val]...
 */

#include <stdint.h>
#include <string.h>

/* IC0 stable memory imports */
extern uint32_t ic0_stable_size_impl(void)
    __attribute__((import_module("ic0"), import_name("stable_size")));
extern uint32_t ic0_stable_grow_impl(uint32_t new_pages)
    __attribute__((import_module("ic0"), import_name("stable_grow")));
extern void ic0_stable_read_impl(uint32_t dst, uint32_t offset, uint32_t size)
    __attribute__((import_module("ic0"), import_name("stable_read")));
extern void ic0_stable_write_impl(uint32_t offset, uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("stable_write")));
extern void ic0_debug_print_impl(uint32_t src, uint32_t size)
    __attribute__((import_module("ic0"), import_name("debug_print")));

/* =============================================================================
 * Constants
 * ============================================================================= */

#define STBT_PAGE_SIZE      4096
#define STBT_HEADER_PAGE    0
#define STBT_MAGIC          0x54425453  /* "STBT" little-endian */

/* Node types */
#define STBT_NODE_INTERNAL  0
#define STBT_NODE_LEAF      1

/* Maximum key/value sizes */
#define STBT_MAX_KEY_SIZE   256
#define STBT_MAX_VAL_SIZE   1024

/* B+Tree order (max children per internal node) */
/* With 4KB pages and 256-byte keys: ~15 keys per node */
#define STBT_ORDER          16
#define STBT_MIN_KEYS       ((STBT_ORDER - 1) / 2)

/* =============================================================================
 * Data Structures (in-memory representation)
 * ============================================================================= */

typedef struct {
    uint32_t magic;
    uint32_t root_page;
    uint32_t page_count;
    uint32_t entry_count;
    uint32_t height;
} StbtHeader;

typedef struct {
    uint8_t node_type;
    uint16_t count;
    uint32_t next_leaf;  /* For leaf nodes */
    uint32_t prev_leaf;  /* For leaf nodes */
    /* Children (for internal) or entries (for leaf) follow */
} StbtNodeHeader;

/* =============================================================================
 * State
 * ============================================================================= */

static StbtHeader stbt_header;
static int stbt_initialized = 0;
static uint8_t stbt_page_buf[STBT_PAGE_SIZE];  /* Working buffer */

/* =============================================================================
 * Low-level Page I/O
 * ============================================================================= */

static void stbt_read_page(uint32_t page_num, uint8_t* buf) {
    uint32_t offset = page_num * STBT_PAGE_SIZE;
    ic0_stable_read_impl((uint32_t)(uintptr_t)buf, offset, STBT_PAGE_SIZE);
}

static void stbt_write_page(uint32_t page_num, const uint8_t* buf) {
    uint32_t offset = page_num * STBT_PAGE_SIZE;
    ic0_stable_write_impl(offset, (uint32_t)(uintptr_t)buf, STBT_PAGE_SIZE);
}

static uint32_t stbt_alloc_page(void) {
    uint32_t page_num = stbt_header.page_count;
    stbt_header.page_count++;

    /* Ensure stable memory capacity */
    uint32_t needed_pages = (stbt_header.page_count * STBT_PAGE_SIZE + 65535) / 65536;
    uint32_t current_pages = ic0_stable_size_impl();
    if (needed_pages > current_pages) {
        ic0_stable_grow_impl(needed_pages - current_pages);
    }

    /* Zero the page */
    memset(stbt_page_buf, 0, STBT_PAGE_SIZE);
    stbt_write_page(page_num, stbt_page_buf);

    return page_num;
}

/* =============================================================================
 * Header Management
 * ============================================================================= */

static void stbt_read_header(void) {
    uint8_t buf[32];
    ic0_stable_read_impl((uint32_t)(uintptr_t)buf, 0, 20);
    stbt_header.magic = buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
    stbt_header.root_page = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
    stbt_header.page_count = buf[8] | (buf[9] << 8) | (buf[10] << 16) | (buf[11] << 24);
    stbt_header.entry_count = buf[12] | (buf[13] << 8) | (buf[14] << 16) | (buf[15] << 24);
    stbt_header.height = buf[16] | (buf[17] << 8) | (buf[18] << 16) | (buf[19] << 24);
}

static void stbt_write_header(void) {
    uint8_t buf[32];
    memset(buf, 0, 32);
    buf[0] = stbt_header.magic & 0xFF;
    buf[1] = (stbt_header.magic >> 8) & 0xFF;
    buf[2] = (stbt_header.magic >> 16) & 0xFF;
    buf[3] = (stbt_header.magic >> 24) & 0xFF;
    buf[4] = stbt_header.root_page & 0xFF;
    buf[5] = (stbt_header.root_page >> 8) & 0xFF;
    buf[6] = (stbt_header.root_page >> 16) & 0xFF;
    buf[7] = (stbt_header.root_page >> 24) & 0xFF;
    buf[8] = stbt_header.page_count & 0xFF;
    buf[9] = (stbt_header.page_count >> 8) & 0xFF;
    buf[10] = (stbt_header.page_count >> 16) & 0xFF;
    buf[11] = (stbt_header.page_count >> 24) & 0xFF;
    buf[12] = stbt_header.entry_count & 0xFF;
    buf[13] = (stbt_header.entry_count >> 8) & 0xFF;
    buf[14] = (stbt_header.entry_count >> 16) & 0xFF;
    buf[15] = (stbt_header.entry_count >> 24) & 0xFF;
    buf[16] = stbt_header.height & 0xFF;
    buf[17] = (stbt_header.height >> 8) & 0xFF;
    buf[18] = (stbt_header.height >> 16) & 0xFF;
    buf[19] = (stbt_header.height >> 24) & 0xFF;
    ic0_stable_write_impl(0, (uint32_t)(uintptr_t)buf, 20);
}

/* =============================================================================
 * Initialization
 * ============================================================================= */

static void stbt_init_if_needed(void) {
    if (stbt_initialized) return;

    uint32_t stable_pages = ic0_stable_size_impl();
    if (stable_pages == 0) {
        /* First time: allocate header page + root leaf */
        ic0_stable_grow_impl(1);  /* At least 1 WASM page (64KB) */

        stbt_header.magic = STBT_MAGIC;
        stbt_header.root_page = 1;  /* Root is page 1 */
        stbt_header.page_count = 2; /* Header + root */
        stbt_header.entry_count = 0;
        stbt_header.height = 1;
        stbt_write_header();

        /* Create empty root leaf */
        memset(stbt_page_buf, 0, STBT_PAGE_SIZE);
        stbt_page_buf[0] = STBT_NODE_LEAF;  /* Leaf node */
        stbt_page_buf[1] = 0;  /* 0 entries */
        stbt_page_buf[2] = 0;
        stbt_write_page(1, stbt_page_buf);
    } else {
        stbt_read_header();
        if (stbt_header.magic != STBT_MAGIC) {
            /* Invalid, reinitialize */
            stbt_header.magic = STBT_MAGIC;
            stbt_header.root_page = 1;
            stbt_header.page_count = 2;
            stbt_header.entry_count = 0;
            stbt_header.height = 1;
            stbt_write_header();

            memset(stbt_page_buf, 0, STBT_PAGE_SIZE);
            stbt_page_buf[0] = STBT_NODE_LEAF;
            stbt_write_page(1, stbt_page_buf);
        }
    }
    stbt_initialized = 1;
}

/* =============================================================================
 * Key Comparison
 * ============================================================================= */

/* Compare two keys: returns -1, 0, or 1 */
static int stbt_key_cmp(const uint8_t* k1, uint16_t len1,
                        const uint8_t* k2, uint16_t len2) {
    uint16_t min_len = (len1 < len2) ? len1 : len2;
    for (uint16_t i = 0; i < min_len; i++) {
        if (k1[i] < k2[i]) return -1;
        if (k1[i] > k2[i]) return 1;
    }
    if (len1 < len2) return -1;
    if (len1 > len2) return 1;
    return 0;
}

/* =============================================================================
 * Leaf Node Operations
 * ============================================================================= */

/*
 * Leaf layout after header (11 bytes):
 *   [key_len:2][key:key_len][val_len:2][val:val_len]...
 */

/* Find key in leaf, returns offset to entry or 0 if not found */
static uint16_t stbt_leaf_find(const uint8_t* page,
                                const uint8_t* key, uint16_t key_len,
                                int* found) {
    uint16_t count = page[1] | (page[2] << 8);
    uint16_t offset = 11;  /* Skip node header */

    *found = 0;
    for (uint16_t i = 0; i < count; i++) {
        uint16_t entry_key_len = page[offset] | (page[offset + 1] << 8);
        int cmp = stbt_key_cmp(key, key_len, &page[offset + 2], entry_key_len);

        if (cmp == 0) {
            *found = 1;
            return offset;
        } else if (cmp < 0) {
            /* Key would be inserted here */
            return offset;
        }

        /* Skip to next entry */
        uint16_t val_len = page[offset + 2 + entry_key_len] |
                           (page[offset + 3 + entry_key_len] << 8);
        offset += 2 + entry_key_len + 2 + val_len;
    }

    return offset;  /* Insert at end */
}

/* Calculate used space in leaf */
static uint16_t stbt_leaf_used_space(const uint8_t* page) {
    uint16_t count = page[1] | (page[2] << 8);
    uint16_t offset = 11;

    for (uint16_t i = 0; i < count; i++) {
        uint16_t key_len = page[offset] | (page[offset + 1] << 8);
        uint16_t val_len = page[offset + 2 + key_len] |
                           (page[offset + 3 + key_len] << 8);
        offset += 2 + key_len + 2 + val_len;
    }

    return offset;
}

/* Insert entry into leaf at position (assumes space available) */
static void stbt_leaf_insert_at(uint8_t* page, uint16_t pos,
                                 const uint8_t* key, uint16_t key_len,
                                 const uint8_t* val, uint16_t val_len) {
    uint16_t count = page[1] | (page[2] << 8);
    uint16_t used = stbt_leaf_used_space(page);
    uint16_t entry_size = 2 + key_len + 2 + val_len;

    /* Shift existing entries */
    if (pos < used) {
        memmove(&page[pos + entry_size], &page[pos], used - pos);
    }

    /* Write new entry */
    page[pos] = key_len & 0xFF;
    page[pos + 1] = (key_len >> 8) & 0xFF;
    memcpy(&page[pos + 2], key, key_len);
    page[pos + 2 + key_len] = val_len & 0xFF;
    page[pos + 3 + key_len] = (val_len >> 8) & 0xFF;
    memcpy(&page[pos + 4 + key_len], val, val_len);

    /* Update count */
    count++;
    page[1] = count & 0xFF;
    page[2] = (count >> 8) & 0xFF;
}

/* =============================================================================
 * Internal Node Operations
 * ============================================================================= */

/*
 * Internal node layout after header (5 bytes):
 *   [child0:4][key0_len:2][key0:len][child1:4][key1_len:2][key1:len]...
 *
 * For n keys, there are n+1 children.
 * Children are page numbers.
 */

/* Find child to descend into for given key */
static uint32_t stbt_internal_find_child(const uint8_t* page,
                                          const uint8_t* key, uint16_t key_len,
                                          int* child_idx) {
    uint16_t count = page[1] | (page[2] << 8);  /* Number of keys */
    uint16_t offset = 5;  /* Skip header */

    /* Read first child */
    uint32_t child = page[offset] | (page[offset + 1] << 8) |
                     (page[offset + 2] << 16) | (page[offset + 3] << 24);
    offset += 4;

    for (uint16_t i = 0; i < count; i++) {
        uint16_t sep_key_len = page[offset] | (page[offset + 1] << 8);
        int cmp = stbt_key_cmp(key, key_len, &page[offset + 2], sep_key_len);

        if (cmp < 0) {
            *child_idx = i;
            return child;
        }

        /* Move to next separator and child */
        offset += 2 + sep_key_len;
        child = page[offset] | (page[offset + 1] << 8) |
                (page[offset + 2] << 16) | (page[offset + 3] << 24);
        offset += 4;
    }

    *child_idx = count;
    return child;  /* Rightmost child */
}

/* =============================================================================
 * Search
 * ============================================================================= */

/*
 * Search for key in B+Tree
 * Returns: value length if found, -1 if not found
 */
int64_t stbt_get(int64_t key_ptr, int64_t key_len,
                 int64_t val_ptr, int64_t max_val_len) {
    stbt_init_if_needed();

    const uint8_t* key = (const uint8_t*)(uintptr_t)key_ptr;
    uint8_t* val = (uint8_t*)(uintptr_t)val_ptr;
    uint16_t k_len = (uint16_t)key_len;
    uint16_t max_len = (uint16_t)max_val_len;

    uint32_t page_num = stbt_header.root_page;

    /* Traverse to leaf */
    for (uint32_t level = 0; level < stbt_header.height - 1; level++) {
        stbt_read_page(page_num, stbt_page_buf);

        if (stbt_page_buf[0] != STBT_NODE_INTERNAL) {
            return -1;  /* Corruption */
        }

        int child_idx;
        page_num = stbt_internal_find_child(stbt_page_buf, key, k_len, &child_idx);
    }

    /* Now at leaf */
    stbt_read_page(page_num, stbt_page_buf);

    if (stbt_page_buf[0] != STBT_NODE_LEAF) {
        return -1;  /* Corruption */
    }

    int found;
    uint16_t pos = stbt_leaf_find(stbt_page_buf, key, k_len, &found);

    if (!found) {
        return -1;
    }

    /* Read value */
    uint16_t entry_key_len = stbt_page_buf[pos] | (stbt_page_buf[pos + 1] << 8);
    uint16_t val_len = stbt_page_buf[pos + 2 + entry_key_len] |
                       (stbt_page_buf[pos + 3 + entry_key_len] << 8);

    uint16_t copy_len = (val_len < max_len) ? val_len : max_len;
    memcpy(val, &stbt_page_buf[pos + 4 + entry_key_len], copy_len);

    return (int64_t)val_len;
}

/* =============================================================================
 * Insert (Simplified - no split for MVP)
 * ============================================================================= */

/*
 * Insert key-value pair
 * Returns: 0 on success, -1 on error (e.g., leaf full)
 *
 * Note: This is a simplified version that doesn't handle node splits.
 * For production, implement proper B+Tree splits.
 */
int64_t stbt_put(int64_t key_ptr, int64_t key_len,
                 int64_t val_ptr, int64_t val_len) {
    stbt_init_if_needed();

    const uint8_t* key = (const uint8_t*)(uintptr_t)key_ptr;
    const uint8_t* val = (const uint8_t*)(uintptr_t)val_ptr;
    uint16_t k_len = (uint16_t)key_len;
    uint16_t v_len = (uint16_t)val_len;

    if (k_len > STBT_MAX_KEY_SIZE || v_len > STBT_MAX_VAL_SIZE) {
        return -1;
    }

    /* For MVP: Only handle single-leaf case (height=1) */
    if (stbt_header.height != 1) {
        /* Multi-level tree - use traversal */
        uint32_t page_num = stbt_header.root_page;

        for (uint32_t level = 0; level < stbt_header.height - 1; level++) {
            stbt_read_page(page_num, stbt_page_buf);
            int child_idx;
            page_num = stbt_internal_find_child(stbt_page_buf, key, k_len, &child_idx);
        }

        stbt_read_page(page_num, stbt_page_buf);

        int found;
        uint16_t pos = stbt_leaf_find(stbt_page_buf, key, k_len, &found);

        if (found) {
            /* Update existing - check if same size */
            uint16_t entry_key_len = stbt_page_buf[pos] | (stbt_page_buf[pos + 1] << 8);
            uint16_t old_val_len = stbt_page_buf[pos + 2 + entry_key_len] |
                                   (stbt_page_buf[pos + 3 + entry_key_len] << 8);

            if (old_val_len == v_len) {
                /* Same size, update in place */
                memcpy(&stbt_page_buf[pos + 4 + entry_key_len], val, v_len);
                stbt_write_page(page_num, stbt_page_buf);
                return 0;
            }
            /* Different size - would need compaction, return error for now */
            return -1;
        }

        /* Check if there's space */
        uint16_t used = stbt_leaf_used_space(stbt_page_buf);
        uint16_t entry_size = 2 + k_len + 2 + v_len;

        if (used + entry_size > STBT_PAGE_SIZE - 64) {  /* Leave some margin */
            /* Would need split - not implemented */
            return -1;
        }

        stbt_leaf_insert_at(stbt_page_buf, pos, key, k_len, val, v_len);
        stbt_write_page(page_num, stbt_page_buf);
        stbt_header.entry_count++;
        stbt_write_header();
        return 0;
    }

    /* Single leaf case */
    stbt_read_page(stbt_header.root_page, stbt_page_buf);

    int found;
    uint16_t pos = stbt_leaf_find(stbt_page_buf, key, k_len, &found);

    if (found) {
        /* Update existing */
        uint16_t entry_key_len = stbt_page_buf[pos] | (stbt_page_buf[pos + 1] << 8);
        uint16_t old_val_len = stbt_page_buf[pos + 2 + entry_key_len] |
                               (stbt_page_buf[pos + 3 + entry_key_len] << 8);

        if (old_val_len == v_len) {
            memcpy(&stbt_page_buf[pos + 4 + entry_key_len], val, v_len);
            stbt_write_page(stbt_header.root_page, stbt_page_buf);
            return 0;
        }
        return -1;  /* Size mismatch */
    }

    /* Check space */
    uint16_t used = stbt_leaf_used_space(stbt_page_buf);
    uint16_t entry_size = 2 + k_len + 2 + v_len;

    if (used + entry_size > STBT_PAGE_SIZE - 64) {
        /* TODO: Implement leaf split */
        return -1;
    }

    stbt_leaf_insert_at(stbt_page_buf, pos, key, k_len, val, v_len);
    stbt_write_page(stbt_header.root_page, stbt_page_buf);
    stbt_header.entry_count++;
    stbt_write_header();

    return 0;
}

/* =============================================================================
 * Utility Functions
 * ============================================================================= */

int64_t stbt_count(void) {
    stbt_init_if_needed();
    return (int64_t)stbt_header.entry_count;
}

int64_t stbt_height(void) {
    stbt_init_if_needed();
    return (int64_t)stbt_header.height;
}

void stbt_clear(void) {
    stbt_header.magic = STBT_MAGIC;
    stbt_header.root_page = 1;
    stbt_header.page_count = 2;
    stbt_header.entry_count = 0;
    stbt_header.height = 1;
    stbt_write_header();

    memset(stbt_page_buf, 0, STBT_PAGE_SIZE);
    stbt_page_buf[0] = STBT_NODE_LEAF;
    stbt_write_page(1, stbt_page_buf);

    stbt_initialized = 1;
}

/* =============================================================================
 * Prefix Scan / Range Query
 * ============================================================================= */

/* Scan state for iterating results */
static uint32_t scan_leaf_page = 0;
static uint16_t scan_leaf_offset = 0;
static uint8_t scan_prefix[STBT_MAX_KEY_SIZE];
static uint16_t scan_prefix_len = 0;
static int scan_active = 0;

/*
 * Check if key starts with prefix
 */
static int stbt_has_prefix(const uint8_t* key, uint16_t key_len,
                            const uint8_t* prefix, uint16_t prefix_len) {
    if (key_len < prefix_len) return 0;
    for (uint16_t i = 0; i < prefix_len; i++) {
        if (key[i] != prefix[i]) return 0;
    }
    return 1;
}

/*
 * Start a prefix scan
 * Returns: number of matching entries (estimate), or -1 on error
 *
 * After calling this, use stbt_scan_next() to iterate results.
 */
int64_t stbt_scan_start(int64_t prefix_ptr, int64_t prefix_len) {
    stbt_init_if_needed();

    const uint8_t* prefix = (const uint8_t*)(uintptr_t)prefix_ptr;
    uint16_t p_len = (uint16_t)prefix_len;

    if (p_len > STBT_MAX_KEY_SIZE) return -1;

    /* Save prefix for iteration */
    memcpy(scan_prefix, prefix, p_len);
    scan_prefix_len = p_len;

    /* Find first matching leaf by traversing tree with prefix as key */
    uint32_t page_num = stbt_header.root_page;

    for (uint32_t level = 0; level < stbt_header.height - 1; level++) {
        stbt_read_page(page_num, stbt_page_buf);
        if (stbt_page_buf[0] != STBT_NODE_INTERNAL) return -1;

        int child_idx;
        page_num = stbt_internal_find_child(stbt_page_buf, prefix, p_len, &child_idx);
    }

    /* Now at leaf - find first matching entry */
    stbt_read_page(page_num, stbt_page_buf);
    if (stbt_page_buf[0] != STBT_NODE_LEAF) return -1;

    uint16_t count = stbt_page_buf[1] | (stbt_page_buf[2] << 8);
    uint16_t offset = 11;

    for (uint16_t i = 0; i < count; i++) {
        uint16_t key_len = stbt_page_buf[offset] | (stbt_page_buf[offset + 1] << 8);

        if (stbt_has_prefix(&stbt_page_buf[offset + 2], key_len, prefix, p_len)) {
            /* Found first match */
            scan_leaf_page = page_num;
            scan_leaf_offset = offset;
            scan_active = 1;
            return 1;  /* At least 1 match */
        }

        /* Check if we've passed where prefix would be */
        if (stbt_key_cmp(&stbt_page_buf[offset + 2], key_len, prefix, p_len) > 0) {
            /* All keys from here are greater than prefix */
            if (!stbt_has_prefix(&stbt_page_buf[offset + 2], key_len, prefix, p_len)) {
                scan_active = 0;
                return 0;  /* No matches */
            }
        }

        /* Skip to next entry */
        uint16_t val_len = stbt_page_buf[offset + 2 + key_len] |
                           (stbt_page_buf[offset + 3 + key_len] << 8);
        offset += 2 + key_len + 2 + val_len;
    }

    /* Check next leaf */
    uint32_t next_leaf = stbt_page_buf[3] | (stbt_page_buf[4] << 8) |
                         (stbt_page_buf[5] << 16) | (stbt_page_buf[6] << 24);
    if (next_leaf == 0) {
        scan_active = 0;
        return 0;
    }

    /* Continue search in next leaf */
    scan_leaf_page = next_leaf;
    scan_leaf_offset = 11;
    scan_active = 1;

    return 1;
}

/*
 * Get next result from prefix scan
 * Copies key and value to provided buffers
 * Returns: 1 if result available, 0 if no more results, -1 on error
 */
int64_t stbt_scan_next(int64_t key_ptr, int64_t max_key_len,
                        int64_t val_ptr, int64_t max_val_len,
                        int64_t out_key_len_ptr, int64_t out_val_len_ptr) {
    if (!scan_active) return 0;

    uint8_t* key_buf = (uint8_t*)(uintptr_t)key_ptr;
    uint8_t* val_buf = (uint8_t*)(uintptr_t)val_ptr;
    uint16_t* out_key_len = (uint16_t*)(uintptr_t)out_key_len_ptr;
    uint16_t* out_val_len = (uint16_t*)(uintptr_t)out_val_len_ptr;
    uint16_t max_k = (uint16_t)max_key_len;
    uint16_t max_v = (uint16_t)max_val_len;

    while (scan_leaf_page != 0) {
        stbt_read_page(scan_leaf_page, stbt_page_buf);

        if (stbt_page_buf[0] != STBT_NODE_LEAF) {
            scan_active = 0;
            return -1;
        }

        uint16_t count = stbt_page_buf[1] | (stbt_page_buf[2] << 8);
        uint16_t offset = scan_leaf_offset;

        /* Calculate entry index from offset */
        uint16_t temp_offset = 11;
        uint16_t entry_idx = 0;
        while (temp_offset < offset && entry_idx < count) {
            uint16_t k_len = stbt_page_buf[temp_offset] | (stbt_page_buf[temp_offset + 1] << 8);
            uint16_t v_len = stbt_page_buf[temp_offset + 2 + k_len] |
                             (stbt_page_buf[temp_offset + 3 + k_len] << 8);
            temp_offset += 2 + k_len + 2 + v_len;
            entry_idx++;
        }

        /* Scan entries from current position */
        while (offset < STBT_PAGE_SIZE - 4 && entry_idx < count) {
            uint16_t key_len = stbt_page_buf[offset] | (stbt_page_buf[offset + 1] << 8);

            if (key_len == 0 || key_len > STBT_MAX_KEY_SIZE) break;

            /* Check if still matching prefix */
            if (!stbt_has_prefix(&stbt_page_buf[offset + 2], key_len,
                                 scan_prefix, scan_prefix_len)) {
                /* Prefix no longer matches - done */
                scan_active = 0;
                return 0;
            }

            uint16_t val_len = stbt_page_buf[offset + 2 + key_len] |
                               (stbt_page_buf[offset + 3 + key_len] << 8);

            /* Copy key */
            uint16_t copy_k = (key_len < max_k) ? key_len : max_k;
            memcpy(key_buf, &stbt_page_buf[offset + 2], copy_k);
            *out_key_len = key_len;

            /* Copy value */
            uint16_t copy_v = (val_len < max_v) ? val_len : max_v;
            memcpy(val_buf, &stbt_page_buf[offset + 4 + key_len], copy_v);
            *out_val_len = val_len;

            /* Advance to next entry */
            scan_leaf_offset = offset + 2 + key_len + 2 + val_len;

            return 1;  /* Result available */
        }

        /* Move to next leaf */
        uint32_t next_leaf = stbt_page_buf[3] | (stbt_page_buf[4] << 8) |
                             (stbt_page_buf[5] << 16) | (stbt_page_buf[6] << 24);
        scan_leaf_page = next_leaf;
        scan_leaf_offset = 11;

        if (next_leaf == 0) {
            scan_active = 0;
            return 0;
        }
    }

    scan_active = 0;
    return 0;
}

/*
 * Stop an active scan
 */
void stbt_scan_stop(void) {
    scan_active = 0;
    scan_leaf_page = 0;
    scan_leaf_offset = 0;
}

/*
 * Convenience: Collect all prefix matches into a buffer
 * Returns: number of matches copied, or -1 on error
 *
 * Buffer format: [count:4][entry0][entry1]...
 * Each entry: [key_len:2][key][val_len:2][val]
 */
int64_t stbt_scan_collect(int64_t prefix_ptr, int64_t prefix_len,
                           int64_t buf_ptr, int64_t buf_size,
                           int64_t max_results) {
    int64_t started = stbt_scan_start(prefix_ptr, prefix_len);
    if (started < 0) return -1;
    if (started == 0) return 0;

    uint8_t* buf = (uint8_t*)(uintptr_t)buf_ptr;
    uint32_t buf_max = (uint32_t)buf_size;
    uint32_t max_res = (uint32_t)max_results;

    uint32_t count = 0;
    uint32_t offset = 4;  /* Reserve space for count */

    uint8_t key_tmp[STBT_MAX_KEY_SIZE];
    uint8_t val_tmp[STBT_MAX_VAL_SIZE];
    uint16_t key_len, val_len;

    while (count < max_res) {
        int64_t result = stbt_scan_next(
            (int64_t)(uintptr_t)key_tmp, STBT_MAX_KEY_SIZE,
            (int64_t)(uintptr_t)val_tmp, STBT_MAX_VAL_SIZE,
            (int64_t)(uintptr_t)&key_len, (int64_t)(uintptr_t)&val_len
        );

        if (result <= 0) break;

        uint32_t entry_size = 2 + key_len + 2 + val_len;
        if (offset + entry_size > buf_max) break;  /* Buffer full */

        /* Write entry to buffer */
        buf[offset] = key_len & 0xFF;
        buf[offset + 1] = (key_len >> 8) & 0xFF;
        memcpy(&buf[offset + 2], key_tmp, key_len);
        buf[offset + 2 + key_len] = val_len & 0xFF;
        buf[offset + 3 + key_len] = (val_len >> 8) & 0xFF;
        memcpy(&buf[offset + 4 + key_len], val_tmp, val_len);

        offset += entry_size;
        count++;
    }

    stbt_scan_stop();

    /* Write count at start */
    buf[0] = count & 0xFF;
    buf[1] = (count >> 8) & 0xFF;
    buf[2] = (count >> 16) & 0xFF;
    buf[3] = (count >> 24) & 0xFF;

    return (int64_t)count;
}
