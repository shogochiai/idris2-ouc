#!/bin/bash
# FFI Bug #3 Reproduction Test Runner
#
# This script builds and runs the FFI test in multiple environments:
# 1. Native (macOS/Linux) - expected to work
# 2. WASM via Emscripten - may reproduce Bug #3
#
# Usage: ./run-test.sh [native|wasm|both]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== FFI Bug #3 Reproduction Test ===${NC}"
echo ""

# =============================================================================
# Step 1: Compile Idris2 to C (RefC backend)
# =============================================================================
build_idris2() {
    echo -e "${YELLOW}>>> Building Idris2 → C (RefC)${NC}"

    # Set GMP include path for Idris2 RefC
    GMP_PREFIX="${GMP_PREFIX:-/opt/homebrew/opt/gmp}"
    export CPATH="$GMP_PREFIX/include:$CPATH"

    idris2 --codegen refc \
        --build-dir "$BUILD_DIR/idris" \
        -o ffi-test \
        FFITest.idr 2>&1 || {
        echo -e "${RED}Idris2 compilation failed${NC}"
        exit 1
    }

    C_FILE=$(find "$BUILD_DIR/idris" -name "*.c" | head -1)
    if [ -z "$C_FILE" ]; then
        echo -e "${RED}No C file generated${NC}"
        exit 1
    fi
    echo "Generated: $C_FILE"

    # Inject FFI forward declarations
    FFI_DECL='/* FFI Forward Declarations */
#include <stdint.h>
int64_t ffi_return_42(void);
int64_t ffi_add_one(int64_t x);
void ffi_set_result(int64_t value);
int64_t ffi_get_result(void);
void ffi_set_arg(int64_t value);
int64_t ffi_get_arg(void);
int64_t ffi_roundtrip(int64_t x);
/* End FFI Declarations */
'
    echo "$FFI_DECL" > "$BUILD_DIR/ffi_header.h"
    cat "$BUILD_DIR/ffi_header.h" "$C_FILE" > "$BUILD_DIR/main_patched.c"
    mv "$BUILD_DIR/main_patched.c" "$C_FILE"
}

# =============================================================================
# Step 2a: Build and run Native test
# =============================================================================
run_native() {
    echo ""
    echo -e "${YELLOW}>>> Building Native executable${NC}"

    # Download RefC runtime sources (same as WASM build)
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
        for f in idris_support.c idris_file.c idris_directory.c idris_util.c idris_support.h idris_file.h idris_directory.h idris_util.h; do
            curl -sLo "$REFC_SRC/$f" "https://raw.githubusercontent.com/idris-lang/Idris2/main/support/c/$f"
        done
    fi

    # Find GMP
    GMP_PREFIX="${GMP_PREFIX:-/opt/homebrew/opt/gmp}"
    if [ ! -d "$GMP_PREFIX" ]; then
        GMP_PREFIX=$(brew --prefix gmp 2>/dev/null || echo "/usr/local")
    fi
    echo "Using GMP: $GMP_PREFIX"
    echo "Using RefC sources: $REFC_SRC"

    C_FILE=$(find "$BUILD_DIR/idris" -name "*.c" | head -1)

    # RefC runtime source files (minimal set for FFI test)
    REFC_FILES="$REFC_SRC/runtime.c $REFC_SRC/memoryManagement.c $REFC_SRC/stringOps.c $REFC_SRC/mathFunctions.c $REFC_SRC/casts.c $REFC_SRC/prim.c $REFC_SRC/refc_util.c"
    # Skip all C support files - FFI test doesn't need file I/O
    C_FILES=""

    # Compile with clang/gcc
    # Use -include to inject FFI declarations before Idris2-generated code
    cc -o "$BUILD_DIR/ffi-test-native" \
        "$C_FILE" \
        ffi_test.c \
        $REFC_FILES \
        $C_FILES \
        -include ffi_test.h \
        -I"$REFC_SRC" \
        -I"$GMP_PREFIX/include" \
        -L"$GMP_PREFIX/lib" \
        -lgmp \
        -lpthread \
        -Wno-implicit-function-declaration \
        2>&1 || {
        echo -e "${RED}Native compilation failed${NC}"
        exit 1
    }

    echo ""
    echo -e "${GREEN}>>> Running Native test${NC}"
    echo "----------------------------------------"
    "$BUILD_DIR/ffi-test-native"
    echo "----------------------------------------"
}

# =============================================================================
# Step 2b: Build and run WASM test (Emscripten)
# =============================================================================
run_wasm() {
    echo ""
    echo -e "${YELLOW}>>> Building WASM executable (Emscripten)${NC}"

    # Source emsdk
    if [ -f "$HOME/emsdk/emsdk_env.sh" ]; then
        source "$HOME/emsdk/emsdk_env.sh" > /dev/null 2>&1
    fi

    if ! command -v emcc &> /dev/null; then
        echo -e "${RED}emcc not found. Install Emscripten.${NC}"
        exit 1
    fi

    # Download RefC runtime if needed
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
        for f in idris_support.c idris_file.c idris_directory.c idris_util.c idris_support.h idris_file.h idris_directory.h idris_util.h; do
            curl -sLo "$REFC_SRC/$f" "https://raw.githubusercontent.com/idris-lang/Idris2/main/support/c/$f"
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

    C_FILE=$(find "$BUILD_DIR/idris" -name "*.c" | head -1)
    REFC_FILES="$REFC_SRC/runtime.c $REFC_SRC/memoryManagement.c $REFC_SRC/stringOps.c $REFC_SRC/mathFunctions.c $REFC_SRC/casts.c $REFC_SRC/prim.c $REFC_SRC/refc_util.c"

    CPATH= CPLUS_INCLUDE_PATH= emcc "$C_FILE" \
        $REFC_FILES \
        "$MINI_GMP/mini-gmp.c" \
        ffi_test.c \
        -include ffi_test.h \
        -I"$MINI_GMP" \
        -I"$REFC_SRC" \
        -I"$SCRIPT_DIR" \
        -o "$BUILD_DIR/ffi-test.js" \
        -s STANDALONE_WASM=0 \
        -s EXIT_RUNTIME=1 \
        -Wno-implicit-function-declaration \
        2>&1 || {
        echo -e "${RED}Emscripten compilation failed${NC}"
        exit 1
    }

    echo ""
    echo -e "${GREEN}>>> Running WASM test (Node.js)${NC}"
    echo "----------------------------------------"
    node "$BUILD_DIR/ffi-test.js"
    echo "----------------------------------------"
}

# =============================================================================
# Main
# =============================================================================

MODE="${1:-both}"

case "$MODE" in
    native)
        build_idris2
        run_native
        ;;
    wasm)
        build_idris2
        run_wasm
        ;;
    both)
        build_idris2
        run_native
        run_wasm

        echo ""
        echo -e "${YELLOW}=== Comparison ===${NC}"
        echo "If Native passes but WASM fails, Bug #3 is reproduced."
        ;;
    *)
        echo "Usage: $0 [native|wasm|both]"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done.${NC}"
