#!/usr/bin/env bash
#
# verify-reproducible-build.sh
#
# Verifies that FABI produces deterministic builds across environments.
# Run this script on multiple machines to confirm reproducibility.
#
# Usage:
#   ./scripts/verify-reproducible-build.sh [--package PACKAGE] [--output FILE]
#
# Options:
#   --package PACKAGE   Package to build (default: idris2-subcontract)
#   --output FILE       Output file for results (default: stdout)
#   --compare FILE      Compare against previous results file
#   --all               Build and verify all packages
#
# Exit codes:
#   0 - Success (build completed, hashes generated)
#   1 - Build failed
#   2 - Hash mismatch detected (when using --compare)

set -euo pipefail

# Default values
PACKAGE="idris2-subcontract"
OUTPUT=""
COMPARE=""
BUILD_ALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --package)
      PACKAGE="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --compare)
      COMPARE="$2"
      shift 2
      ;;
    --all)
      BUILD_ALL=true
      shift
      ;;
    -h|--help)
      head -30 "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Get system info for the report
get_system_info() {
  echo "=== System Information ==="
  echo "Hostname: $(hostname)"
  echo "OS: $(uname -s) $(uname -r)"
  echo "Arch: $(uname -m)"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Nix version: $(nix --version 2>/dev/null || echo 'not installed')"
  echo ""
}

# Build a single package and collect hashes
build_package() {
  local pkg="$1"

  log_info "Building $pkg..."

  # Build with Nix
  if ! nix build ".#$pkg" --no-link --print-out-paths > /tmp/build_output_$$.txt 2>&1; then
    log_error "Build failed for $pkg"
    cat /tmp/build_output_$$.txt
    rm -f /tmp/build_output_$$.txt
    return 1
  fi

  local out_path
  out_path=$(cat /tmp/build_output_$$.txt)
  rm -f /tmp/build_output_$$.txt

  log_info "Build output: $out_path"

  echo "=== Package: $pkg ==="
  echo "Output path: $out_path"
  echo ""

  # Calculate hashes for all relevant files
  echo "--- TTC Files ---"
  if [[ -d "$out_path/lib" ]]; then
    find "$out_path/lib" -name "*.ttc" -type f | sort | while read -r f; do
      local relpath="${f#$out_path/}"
      local hash
      hash=$(sha256sum "$f" | cut -d' ' -f1)
      echo "$hash  $relpath"
    done
  fi

  echo ""
  echo "--- Binary Files ---"
  if [[ -d "$out_path/bin" ]]; then
    find "$out_path/bin" -type f | sort | while read -r f; do
      local relpath="${f#$out_path/}"
      local hash
      hash=$(sha256sum "$f" | cut -d' ' -f1)
      echo "$hash  $relpath"
    done
  fi

  echo ""
  echo "--- Store Path Hash ---"
  # The Nix store path contains a hash of all inputs
  local store_hash
  store_hash=$(basename "$out_path" | cut -d'-' -f1)
  echo "Store path hash: $store_hash"
  echo ""

  return 0
}

# All packages to verify
ALL_PACKAGES=(
  "idris2-cdk"
  "idris2-yul"
  "idris2-subcontract"
)

# Main execution
main() {
  local result_file
  result_file=$(mktemp)

  {
    echo "========================================"
    echo "  FABI Reproducible Build Verification"
    echo "========================================"
    echo ""
    get_system_info

    if $BUILD_ALL; then
      for pkg in "${ALL_PACKAGES[@]}"; do
        if ! build_package "$pkg"; then
          log_error "Failed to build $pkg"
          exit 1
        fi
        echo ""
      done
    else
      if ! build_package "$PACKAGE"; then
        exit 1
      fi
    fi

    echo "========================================"
    echo "  Verification Complete"
    echo "========================================"

  } | tee "$result_file"

  # Output to file if specified
  if [[ -n "$OUTPUT" ]]; then
    cp "$result_file" "$OUTPUT"
    log_info "Results written to $OUTPUT"
  fi

  # Compare with previous results if specified
  if [[ -n "$COMPARE" ]]; then
    log_info "Comparing with $COMPARE..."

    # Extract hashes from both files
    local current_hashes previous_hashes
    current_hashes=$(grep -E '^[a-f0-9]{64}' "$result_file" | sort)
    previous_hashes=$(grep -E '^[a-f0-9]{64}' "$COMPARE" | sort)

    if [[ "$current_hashes" == "$previous_hashes" ]]; then
      log_info "All hashes match! Build is reproducible."
    else
      log_error "Hash mismatch detected!"
      echo ""
      echo "Differences:"
      diff <(echo "$previous_hashes") <(echo "$current_hashes") || true
      rm -f "$result_file"
      exit 2
    fi
  fi

  rm -f "$result_file"
}

# Check prerequisites
check_prerequisites() {
  if ! command -v nix &> /dev/null; then
    log_error "Nix is not installed. Please install Nix first."
    echo "Visit: https://nixos.org/download.html"
    exit 1
  fi

  if [[ ! -f "flake.nix" ]]; then
    log_error "flake.nix not found. Run this script from the idris2-ouc root directory."
    exit 1
  fi
}

check_prerequisites
main
