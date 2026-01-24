#!/bin/bash
# OUC E2E Test Data Seeding Script
# Seeds mock data for E2E testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== OUC E2E Test Data Seeding ==="

# Load canister IDs
if [ -f "$PROJECT_DIR/.env.local" ]; then
    source "$PROJECT_DIR/.env.local"
else
    echo "Error: .env.local not found. Run deploy-local.sh first."
    exit 1
fi

echo "OUC Canister: $OUC_CANISTER_ID"
echo ""

# 1. Verify canister is running
echo "[1/5] Verifying OUC canister..."
VERSION=$(dfx canister call ouc getVersion --network local 2>/dev/null | tr -d '()' | tr -d ' ')
echo "  Version: $VERSION"

# 2. Check existing auditors
echo ""
echo "[2/5] Checking existing auditors..."
AUDITORS=$(dfx canister call ouc getAuditors --network local 2>/dev/null)
echo "  Current auditors: $AUDITORS"

# 3. Store test events
echo ""
echo "[3/5] Storing test events..."
# storeTestEvent(blockNumber, eventType)
# eventType: 0=UpgradeProposed, 1=VoteCast, 2=ProposalExecuted

dfx canister call ouc storeTestEvent '(1000000 : nat, 0 : nat)' --network local
echo "  Event 1: UpgradeProposed at block 1000000"

dfx canister call ouc storeTestEvent '(1000001 : nat, 1 : nat)' --network local
echo "  Event 2: VoteCast at block 1000001"

dfx canister call ouc storeTestEvent '(1000002 : nat, 1 : nat)' --network local
echo "  Event 3: VoteCast at block 1000002"

dfx canister call ouc storeTestEvent '(1000003 : nat, 2 : nat)' --network local
echo "  Event 4: ProposalExecuted at block 1000003"

dfx canister call ouc storeTestEvent '(1000010 : nat, 0 : nat)' --network local
echo "  Event 5: UpgradeProposed at block 1000010"

# 4. Verify data
echo ""
echo "[4/5] Verifying seeded data..."
echo "  Auditors:"
dfx canister call ouc getAuditors --network local

echo ""
echo "  Subscription:"
dfx canister call ouc getSubscription --network local

echo ""
echo "  Treasury:"
dfx canister call ouc getTreasury --network local

echo ""
echo "  Dashboard Summary (event count):"
dfx canister call ouc getDashboardSummary --network local

echo ""
echo "  OUC Events (limit 10):"
dfx canister call ouc getOucEvents '(10 : nat)' --network local

# 5. Summary
echo ""
echo "[5/5] Test data seeding complete!"
echo ""
echo "=== Summary ==="
echo "  - 2 mock auditors (Alice, Bob)"
echo "  - 5 test events stored"
echo "  - Standard tier subscription"
echo "  - Treasury balances set"
echo ""
echo "You can now run E2E tests against:"
echo "  Dashboard: http://$DASHBOARD_CANISTER_ID.localhost:4943"
