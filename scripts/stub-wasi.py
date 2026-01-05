#!/usr/bin/env python3
"""
Stub WASI imports in a WAT file by replacing them with local functions.
Usage: python stub-wasi.py input.wat output.wat
"""
import re
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: stub-wasi.py input.wat output.wat")
        sys.exit(1)

    with open(sys.argv[1], "r") as f:
        lines = f.readlines()

    # Find and remove WASI import lines, track where last ic0 import is
    output_lines = []
    last_ic0_idx = -1

    for i, line in enumerate(lines):
        if 'wasi_snapshot_preview1' in line:
            # Skip WASI import lines
            continue
        output_lines.append(line)
        if '(import "ic0"' in line:
            last_ic0_idx = len(output_lines) - 1

    # Stub function definitions - these replace WASI imports
    # type 3: (param i32) (result i32) - fd_close
    # type 9: (param i32 i32 i32 i32) (result i32) - fd_write
    # type 24: (param i32 i64 i32 i32) (result i32) - fd_seek
    stub_funcs = [
        "  ;; WASI stub functions (replacing imports)\n",
        "  (func (;3;) (type 3) (param i32) (result i32) i32.const 0)\n",
        "  (func (;4;) (type 9) (param i32 i32 i32 i32) (result i32) i32.const 0)\n",
        "  (func (;5;) (type 24) (param i32 i64 i32 i32) (result i32) i32.const 0)\n",
    ]

    # Insert stub functions after the last ic0 import
    if last_ic0_idx >= 0:
        output_lines = output_lines[:last_ic0_idx+1] + stub_funcs + output_lines[last_ic0_idx+1:]

    with open(sys.argv[2], "w") as f:
        f.writelines(output_lines)

    print("WASI stubs inserted successfully")

if __name__ == "__main__":
    main()
