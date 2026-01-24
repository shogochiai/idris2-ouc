#!/bin/bash
# OUC E2E Integration Tests
# Tests OUC ↔ Dashboard integration

# Don't exit on error - we want to run all tests
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== OUC Integration Tests ==="

# Load canister IDs
if [ -f "$PROJECT_DIR/.env.local" ]; then
    source "$PROJECT_DIR/.env.local"
else
    echo "Error: .env.local not found. Run deploy-local.sh first."
    exit 1
fi

PASSED=0
FAILED=0

# Test helper
run_test() {
    local name="$1"
    local cmd="$2"
    local expected="$3"

    echo -n "  $name... "
    result=$(eval "$cmd" 2>/dev/null || echo "ERROR")

    if echo "$result" | grep -q "$expected"; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL"
        echo "    Expected: $expected"
        echo "    Got: $result"
        ((FAILED++))
    fi
}

# =============================================================================
# 5.4.2.1 OUC ↔ Indexer Sync Tests
# =============================================================================
echo ""
echo "[Test Suite 1] OUC Query Methods"

run_test "getVersion returns nat" \
    "dfx canister call ouc getVersion --network local" \
    ": nat"

run_test "getAuditors returns JSON with Alice" \
    "dfx canister call ouc getAuditors --network local" \
    "Alice"

run_test "getAuditors returns JSON with Bob" \
    "dfx canister call ouc getAuditors --network local" \
    "Bob"

run_test "getSubscription returns Standard tier" \
    "dfx canister call ouc getSubscription --network local" \
    "Standard"

run_test "getTreasury returns ckEthBalance" \
    "dfx canister call ouc getTreasury --network local" \
    "ckEthBalance"

run_test "getProposalCount returns nat" \
    "dfx canister call ouc getProposalCount --network local" \
    ": nat"

run_test "getAuditorCount returns nat" \
    "dfx canister call ouc getAuditorCount --network local" \
    ": nat"

# =============================================================================
# 5.4.2.2 Event Indexer Tests
# =============================================================================
echo ""
echo "[Test Suite 2] Event Indexer Methods"

run_test "getDashboardSummary returns event count" \
    "dfx canister call ouc getDashboardSummary --network local" \
    ": nat"

run_test "getOucEvents returns count for limit" \
    "dfx canister call ouc getOucEvents '(5 : nat)' --network local" \
    ": nat"

run_test "storeTestEvent increments count" \
    "dfx canister call ouc storeTestEvent '(9999999 : nat, 0 : nat)' --network local" \
    ": nat"

# =============================================================================
# 5.4.2.3 Subscription Management Tests
# =============================================================================
echo ""
echo "[Test Suite 3] Subscription Management"

run_test "setTier Economy returns subscription" \
    "dfx canister call ouc setTier '(variant { Economy })' --network local" \
    "Economy"

run_test "setTier RealTime returns subscription" \
    "dfx canister call ouc setTier '(variant { RealTime })' --network local" \
    "RealTime"

run_test "setAutoRenew false works" \
    "dfx canister call ouc setAutoRenew '(false)' --network local" \
    "false"

run_test "setAutoRenew true works" \
    "dfx canister call ouc setAutoRenew '(true)' --network local" \
    "true"

# Reset to Standard
dfx canister call ouc setTier '(variant { Standard })' --network local >/dev/null 2>&1

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Test Summary ==="
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
