# Auditor Verification Workflow

## E2E Flow: FABI → OUC → EVM Execution

This document describes the complete auditor verification workflow for Self-Amending Protocol upgrades.

---

## 1. Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Source Code                                                                 │
│  (idris2-subcontract / idris2-yul / idris2-ouf)                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: FABI (Failure-Aware Build Infrastructure)                         │
│  ─────────────────────────────────────────────────────────────────────────  │
│  nix build → Bytecode + Evidence                                            │
│                                                                             │
│  Outputs:                                                                    │
│    - bytecode.bin (deterministic EVM bytecode)                              │
│    - bytecode.bin.sha256 (reproducibility proof)                            │
│    - flake.lock (environment pinning)                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: Proposal Submission                                               │
│  ─────────────────────────────────────────────────────────────────────────  │
│  dfx canister call ouc submitProposal                                       │
│                                                                             │
│  Payload:                                                                    │
│    - chainId: Target EVM chain                                              │
│    - target: ERC-7546 Proxy address                                         │
│    - newImpl: New implementation address                                    │
│    - ou: OptimisticUpgrader contract                                        │
│    - codeHash: SHA256 of bytecode (FABI evidence)                           │
│    - rationale: Human-readable justification                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: Auditor Assignment (Commit-Reveal VRF)                            │
│  ─────────────────────────────────────────────────────────────────────────  │
│  AuditorPool.selectAuditorsVRF                                              │
│                                                                             │
│  Selection Algorithm:                                                        │
│    1. Commit: hash(blockHash || proposalId || nonce)                        │
│    2. Wait: Reveal window                                                    │
│    3. Reveal: Provide nonce, verify against commit                          │
│    4. Select: Weighted random using revealed seed                           │
│       - Weight = reputation × stakedAmount                                  │
│                                                                             │
│  Criteria:                                                                   │
│    - status == Active                                                        │
│    - reputation >= minReputationScore (default: 500/1000)                   │
│    - stakedAmount >= minStake (default: 1000 tokens)                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: Auditor Verification (Reproducible Build)                         │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Step 4.1: Source Verification                                              │
│    - Clone source repository at specified commit                            │
│    - Verify flake.lock matches proposal                                      │
│                                                                             │
│  Step 4.2: Reproducible Build                                               │
│    $ nix build .#<contract>                                                 │
│    $ sha256sum result/*.bin                                                 │
│                                                                             │
│  Step 4.3: Hash Match Verification                                          │
│    - Compare computed hash with proposal.codeHash                           │
│    - If mismatch: REJECT immediately (f_repro failure)                      │
│                                                                             │
│  Step 4.4: Code Audit (if hash matches)                                     │
│    - Type safety review (Idris2 proofs)                                     │
│    - Business logic verification                                             │
│    - Security analysis                                                       │
│                                                                             │
│  Decision:                                                                   │
│    - ApproveUpgrade: Code is safe and matches claimed bytecode              │
│    - RejectUpgrade(reason): Security issue or hash mismatch                 │
│    - RequestChanges(changes): Non-critical issues to address                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: Review Submission                                                  │
│  ─────────────────────────────────────────────────────────────────────────  │
│  dfx canister call ouc submitReview                                         │
│                                                                             │
│  Payload:                                                                    │
│    - proposalId: ID of the proposal                                         │
│    - decision: ApproveUpgrade | RejectUpgrade | RequestChanges              │
│    - comment: Detailed audit notes                                          │
│    - signature: Auditor's cryptographic signature                           │
│                                                                             │
│  State Transition:                                                           │
│    UnderReview + ApproveUpgrade    → Approved                               │
│    UnderReview + RejectUpgrade     → Rejected                               │
│    UnderReview + RequestChanges    → UnderReview (awaiting fixes)           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                           ┌──────────┴──────────┐
                           │                     │
                      [Approved]            [Rejected]
                           │                     │
                           ▼                     ▼
┌─────────────────────────────────────┐   ┌─────────────────────┐
│  PHASE 6: Execution                  │   │  Flow Ends          │
│  ────────────────────────────────── │   │  (Proposal archived) │
│                                      │   └─────────────────────┘
│  Step 6.1: Signature Aggregation     │
│    - Collect n-of-n auditor sigs     │
│    - Verify all signatures valid     │
│                                      │
│  Step 6.2: Build Upgrade Calldata    │
│    - Encode setImplementation call   │
│    - Attach signature bundle         │
│                                      │
│  Step 6.3: HTTP Outcall to EVM       │
│    - ic0_call_new to management      │
│    - eth_sendRawTransaction          │
│                                      │
│  Step 6.4: Confirmation              │
│    - Wait for tx confirmation        │
│    - Verify implementation changed   │
│    - Mark proposal as Executed       │
└─────────────────────────────────────┘
```

---

## 2. Auditor Pool Management

### 2.1 Registration

```idris
-- AuditorPool/Core.idr:88-109
registerAuditor : List Auditor -> ICPrincipal -> Nat -> Nat -> PoolConfig
               -> FR (List Auditor, AuditorId)
```

Requirements:
- `stakeAmount >= minStake` (default: 1000 tokens)
- Principal must not already be registered
- Initial reputation: 500/1000

### 2.2 Selection Criteria

| Criteria | Description |
|----------|-------------|
| ByReputation | Highest reputation first |
| ByAvailability | Least loaded auditors |
| Random(seed) | Randomized via commit-reveal |
| Weighted | reputation × stakedAmount |

### 2.3 Reputation Updates

```idris
-- After successful review
updateReputation : auditors -> auditorId -> delta -> FR (List Auditor)

-- Positive delta: Good review → reputation up (max 1000)
-- Negative delta: Bad review → reputation down (min 0)
```

### 2.4 Slashing

```idris
-- For misbehavior (false approvals, missed deadlines)
slashAuditor : auditors -> auditorId -> reason -> config -> FR (List Auditor, Nat)

-- Effects:
--   - status := Slashed
--   - stakedAmount -= slashPercentage% (default: 10%)
--   - slashCount += 1
```

---

## 3. Proposal Lifecycle

```
                        ┌─────────┐
                        │ Pending │ ← Initial state after submission
                        └────┬────┘
                             │ assignAuditor()
                             ▼
                      ┌─────────────┐
                      │ UnderReview │
                      └──────┬──────┘
                             │ submitReview()
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │ Approved │   │ Rejected │   │(loop back│
       └────┬─────┘   └──────────┘   │  w/fixes)│
            │                         └──────────┘
            │ executeUpgrade()
            ▼
       ┌──────────┐
       │ Executed │
       └──────────┘

  Additional states:
    - Expired: expiresAt exceeded (7 days default)
    - Cancelled: Proposer withdrew
```

---

## 4. Reproducible Build Verification

### 4.1 FABI Evidence

Every proposal must include evidence from FABI:

```bash
# Build with Nix (deterministic)
nix build .#idris2-subcontract

# Generate evidence
sha256sum result/lib/idris2-0.8.0/idris2-subcontract-0.1.0/*.ttc > evidence.sha256
```

### 4.2 Auditor Verification Script

```bash
#!/usr/bin/env bash
# verify-proposal.sh

PROPOSAL_ID=$1
EXPECTED_HASH=$2  # From proposal.codeHash

# 1. Clone source at specified commit
git clone --depth 1 --branch <commit> <repo> /tmp/verify

# 2. Enter Nix environment
cd /tmp/verify
nix develop --command bash << 'EOF'
  # 3. Build
  nix build .#<contract>

  # 4. Compare hash
  ACTUAL_HASH=$(sha256sum result/*.bin | cut -d' ' -f1)

  if [ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]; then
    echo "✓ Hash match: $ACTUAL_HASH"
    exit 0
  else
    echo "✗ Hash mismatch!"
    echo "  Expected: $EXPECTED_HASH"
    echo "  Actual:   $ACTUAL_HASH"
    exit 1
  fi
EOF
```

---

## 5. Failure Modes and Rebinding

### 5.1 FABI Layer Failures

| Failure | Description | Rebinding |
|---------|-------------|-----------|
| f_env | Build environment corrupted | Use different builder |
| f_repro | Non-reproducible build | Debug with FABI evidence |

### 5.2 OUC Layer Failures

| Failure | Description | Rebinding |
|---------|-------------|-----------|
| f_code | Malicious code detected | Reject proposal, slash proposer |
| f_audit | Auditor unavailable | Reassign to different auditor |
| f_liveness | Execution stalled | Emergency timeout path |

### 5.3 Execution Failures

| Result | Action |
|--------|--------|
| UpgradeSuccess | Mark Executed, update reputation +10 |
| UpgradeReverted | Log failure, reputation unchanged |
| UpgradeTimeout | Retry with higher gas, or expire |
| UpgradeRejected | Archive proposal |

---

## 6. n-of-n Audit Requirement

For an upgrade to proceed:

1. **All** assigned auditors must approve
2. **Any** rejection blocks the upgrade
3. Missing votes cause expiration (not approval)

```idris
-- OUC-Spec.md:64-78
∀ a ∈ A, a ⊨ match(b, c)
```

Where:
- `A` : Set of assigned auditors
- `b` : Proposed bytecode
- `c` : Source code
- `match` : Reproducible build verification

---

## 7. Integration Points

### 7.1 lazy evm-lifecycle → OUC

```
lazy evm-lifecycle ask → detectPendingUpgrades → recommendAuditors
                                    │
                                    ▼
                         OUC.receiveFromLifecycle()
```

### 7.2 Claude Skills

| Command | Function |
|---------|----------|
| /check-upgrade | Query pending upgrades via lazy evm-lifecycle |
| /propose-upgrade | Generate and submit upgrade proposal |
| ouc-onchain | Fetch on-chain state for analysis |
| ouc-monitor | Continuous monitoring loop |

---

## 8. Quick Reference

### CLI Commands

```bash
# Submit proposal
dfx canister call ouc submitProposal '(
  record {
    chainId = 1;
    target = "0x...";
    newImpl = "0x...";
    ou = "0x...";
    rationale = "Bug fix for issue #123";
    codeHash = "abc123...";
  }
)'

# Get proposal
dfx canister call ouc getProposal '(0 : nat)'

# Submit review
dfx canister call ouc submitReview '(
  record {
    proposalId = 0;
    decision = variant { ApproveUpgrade };
    comment = "Verified reproducible build, code review passed";
    signature = "0x...";
  }
)'

# Check counts
dfx canister call ouc getProposalCount
dfx canister call ouc getAuditorCount
```

### Module Map

| Responsibility | Module |
|----------------|--------|
| Proposal CRUD | src/Proposals/Core.idr |
| Auditor Pool | src/AuditorPool/Core.idr |
| ERC-7546 Upgrade | src/ERC7546/Upgrade.idr |
| HTTP Outcall | src/HttpOutcall/Core.idr |
| Failure Routing | FRMonad.Core (idris2-cdk) |

---

## References

- [FABI.md](./FABI.md) - Failure-Aware Build Infrastructure
- [OUC-Spec.md](./OUC-Spec.md) - OUC Formal Specification
- [ecosystem.md](./ecosystem.md) - Full Architecture Overview
