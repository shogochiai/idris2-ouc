#!/bin/bash
# IC0 FFI Bug #3 Test Builder
#
# This script builds the IC0 test canister for deployment to dfx.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== IC0 FFI Bug #3 Test Build ===${NC}"

# =============================================================================
# Step 1: Compile Idris2 to C
# =============================================================================
echo -e "${YELLOW}>>> Compiling Idris2 → C${NC}"

# GMP include path
GMP_PREFIX="${GMP_PREFIX:-/opt/homebrew/opt/gmp}"
export CPATH="$GMP_PREFIX/include:$CPATH"

idris2 --codegen refc \
    --build-dir "$BUILD_DIR/idris" \
    -o ic0-test \
    IC0Test.idr 2>&1 || {
    echo -e "${RED}Idris2 compilation failed${NC}"
    exit 1
}

C_FILE=$(find "$BUILD_DIR/idris" -name "*.c" | head -1)
if [ -z "$C_FILE" ]; then
    echo -e "${RED}No C file generated${NC}"
    exit 1
fi
echo "Generated: $C_FILE"

# =============================================================================
# Step 2: Download dependencies
# =============================================================================
REFC_SRC="/tmp/refc-src"
MINI_GMP="/tmp/mini-gmp"

if [ ! -f "$REFC_SRC/runtime.c" ]; then
    echo "Downloading RefC runtime..."
    mkdir -p "$REFC_SRC"
    for f in memoryManagement.c runtime.c stringOps.c mathFunctions.c casts.c clock.c buffer.c prim.c refc_util.c; do
        curl -sLo "$REFC_SRC/$f" "https://raw.githubusercontent.com/idris-lang/Idris2/main/support/refc/$f"
    done
    for f in runtime.h cBackend.h datatypes.h _datatypes.h refc_util.h mathFunctions.h memoryManagement.h stringOps.h casts.h clock.h buffer.h prim.h threads.h; do
        curl -sLo "$REFC_SRC/$f" "https://raw.githubusercontent.com/idris-lang/Idris2/main/support/refc/$f"
    done
fi

if [ ! -f "$MINI_GMP/mini-gmp.c" ]; then
    echo "Downloading mini-gmp..."
    mkdir -p "$MINI_GMP"
    curl -sLo "$MINI_GMP/mini-gmp.c" https://gmplib.org/repo/gmp/raw-file/tip/mini-gmp/mini-gmp.c
    curl -sLo "$MINI_GMP/mini-gmp.h" https://gmplib.org/repo/gmp/raw-file/tip/mini-gmp/mini-gmp.h
    cat > "$MINI_GMP/gmp.h" << 'GMPEOF'
#ifndef GMP_WRAPPER_H
#define GMP_WRAPPER_H
#include "mini-gmp.h"
#include <stdarg.h>
static inline void mpz_inits(mpz_t x, ...) {
    va_list ap; va_start(ap, x); mpz_init(x);
    while ((x = va_arg(ap, mpz_ptr)) != NULL) mpz_init(x);
    va_end(ap);
}
static inline void mpz_clears(mpz_t x, ...) {
    va_list ap; va_start(ap, x); mpz_clear(x);
    while ((x = va_arg(ap, mpz_ptr)) != NULL) mpz_clear(x);
    va_end(ap);
}
#endif
GMPEOF
fi

# =============================================================================
# Step 3: Compile to WASM
# =============================================================================
echo -e "${YELLOW}>>> Compiling C → WASM${NC}"

# Source emsdk
if [ -f "$HOME/emsdk/emsdk_env.sh" ]; then
    source "$HOME/emsdk/emsdk_env.sh" > /dev/null 2>&1
fi

if ! command -v emcc &> /dev/null; then
    echo -e "${RED}emcc not found. Install Emscripten.${NC}"
    exit 1
fi

# Create FFI header for implicit function declarations
cat > "$BUILD_DIR/ffi_decls.h" << 'EOF'
#ifndef FFI_DECLS_H
#define FFI_DECLS_H
#include <stdint.h>

/* IC0 stubs */
int64_t ic0_time(void);
void ic0_debug_print(int64_t src, int64_t size);
void ic0_msg_reply(void);
void ic0_msg_reply_data_append(int64_t src, int64_t size);

/* Test functions */
int64_t test_get_time_direct(void);
void test_set_result(int64_t value);
int64_t test_get_result(void);
void test_debug_int(int64_t value);

#endif
EOF

REFC_FILES="$REFC_SRC/runtime.c $REFC_SRC/memoryManagement.c $REFC_SRC/stringOps.c $REFC_SRC/mathFunctions.c $REFC_SRC/casts.c $REFC_SRC/prim.c $REFC_SRC/refc_util.c"

CPATH= CPLUS_INCLUDE_PATH= emcc "$C_FILE" \
    $REFC_FILES \
    "$MINI_GMP/mini-gmp.c" \
    ic0_test_stubs.c \
    wasi_stubs.c \
    -include "$BUILD_DIR/ffi_decls.h" \
    -I"$MINI_GMP" \
    -I"$REFC_SRC" \
    -o "$BUILD_DIR/ic0_test.wasm" \
    -s STANDALONE_WASM=1 \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
    -s PURE_WASI=1 \
    --no-entry \
    -Wno-implicit-function-declaration \
    -O0 \
    2>&1 || {
    echo -e "${RED}WASM compilation failed${NC}"
    exit 1
}

echo -e "${GREEN}>>> Emscripten build complete${NC}"

# =============================================================================
# Step 4: Stub WASI imports (ICP doesn't support WASI)
# =============================================================================
echo -e "${YELLOW}>>> Stubbing WASI imports${NC}"

if command -v wasm2wat >/dev/null 2>&1 && command -v wat2wasm >/dev/null 2>&1; then
    wasm2wat "$BUILD_DIR/ic0_test.wasm" -o "$BUILD_DIR/ic0_test.wat"

    # Replace WASI imports with stub functions
    # Format: (import "wasi_snapshot_preview1" "fd_close" (func (;N;) (type M)))
    sed -i.bak \
        -e 's|(import "wasi_snapshot_preview1" "fd_close" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_fd_close (param i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "fd_write" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_fd_write (param i32 i32 i32 i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "fd_seek" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_fd_seek (param i32 i64 i32 i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "fd_read" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_fd_read (param i32 i32 i32 i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "environ_sizes_get" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_environ_sizes_get (param i32 i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "environ_get" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_environ_get (param i32 i32) (result i32) i32.const 0)|g' \
        -e 's|(import "wasi_snapshot_preview1" "proc_exit" (func (;[0-9]*;) (type [0-9]*)))|(func $__wasi_proc_exit (param i32))|g' \
        "$BUILD_DIR/ic0_test.wat"

    wat2wasm "$BUILD_DIR/ic0_test.wat" -o "$BUILD_DIR/ic0_test.wasm" || {
        echo -e "${RED}WASI stubbing failed${NC}"
        exit 1
    }
    echo "WASI imports stubbed"
else
    echo -e "${YELLOW}wabt not found, skipping WASI stubbing${NC}"
fi

# Show WASM info
wasm_size=$(wc -c < "$BUILD_DIR/ic0_test.wasm")
echo -e "${GREEN}>>> Build complete: $BUILD_DIR/ic0_test.wasm${NC}"
echo "WASM size: $wasm_size bytes"

# List exports
echo ""
echo "Exports:"
wasm2wat "$BUILD_DIR/ic0_test.wasm" 2>/dev/null | grep '(export' | head -10 || echo "(wasm2wat not available)"

# List imports (should only be ic0.*)
echo ""
echo "Imports (should only be ic0.*):"
wasm2wat "$BUILD_DIR/ic0_test.wasm" 2>/dev/null | grep '(import' | head -10 || echo "(wasm2wat not available)"

echo ""
echo -e "${GREEN}Done. Deploy with: dfx deploy --network local${NC}"
