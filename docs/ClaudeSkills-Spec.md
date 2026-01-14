# Claude Skills Specification

## OUC AI Agent Infrastructure

---

## 1. Overview

Claude Code skills provide specialized capabilities for interacting with the OUC (Optimistic Upgrader Canister) ecosystem. These skills enable AI-assisted monitoring, upgrade detection, and proposal management.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Claude Skills Architecture                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Skills (Knowledge + Patterns)                                              │
│  ├── ouc-onchain      Query EVM/ICP on-chain data                          │
│  └── ouc-monitor      Continuous monitoring and alerting                   │
│                                                                             │
│  Commands (Actions)                                                          │
│  ├── /check-upgrade   Detect pending ERC-7546 upgrades                     │
│  └── /propose-upgrade Generate and submit upgrade proposals                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Skills

### 2.1 ouc-onchain

**Location:** `.claude/skills/ouc-onchain/SKILL.md`

**Purpose:** Query on-chain data from EVM (via `cast`) and ICP (via `dfx`).

**Allowed Tools:** `Bash`, `Read`

**Capabilities:**

| Category | Function | Tool |
|----------|----------|------|
| EVM Query | Get implementation for selector | `cast call` |
| EVM Query | Read storage slot | `cast storage` |
| EVM Query | Get block number | `cast block-number` |
| EVM Query | Check if address has code | `cast codesize` |
| ICP Query | Get OUC version | `dfx canister call` |
| ICP Query | Get proposal count | `dfx canister call` |
| ICP Query | Get specific proposal | `dfx canister call` |
| ICP Query | Get auditor count | `dfx canister call` |
| ICP Query | Get canister status | `dfx canister status` |

**EVM Patterns:**

```bash
# Query ERC-7546 Dictionary
cast call $DICTIONARY_ADDR "getImplementation(bytes4)(address)" $SELECTOR --rpc-url $RPC_URL

# Read proxy's dictionary slot (ERC-7201)
DICTIONARY_SLOT="0x267691be3525af8a813d30db0c9e2bad5b0d2c0f67d9e4f1c769018cff56f4"
cast storage $PROXY_ADDR $DICTIONARY_SLOT --rpc-url $RPC_URL
```

**ICP Patterns:**

```bash
# Query OUC canister
dfx canister call ouc getVersion
dfx canister call ouc getProposalCount
dfx canister call ouc getProposal '(0)'
```

**Environment Variables:**

| Variable | Description | Default |
|----------|-------------|---------|
| `RPC_URL` | EVM RPC endpoint | `https://eth.llamarpc.com` |
| `DICTIONARY_ADDR` | ERC-7546 Dictionary address | - |
| `PROXY_ADDR` | ERC-7546 Proxy address | - |
| `DFX_NETWORK` | ICP network | `local` |

---

### 2.2 ouc-monitor

**Location:** `.claude/skills/ouc-monitor/SKILL.md`

**Purpose:** Continuous monitoring of OUC ecosystem for anomalies and changes.

**Allowed Tools:** `Bash`, `Read`, `Grep`, `WebFetch`

**Monitoring Targets:**

| Target | Trigger | Action |
|--------|---------|--------|
| Dictionary changes | New selector added | Log + potential proposal |
| Dictionary changes | Implementation changed | Alert + propose audit |
| Dictionary changes | Selector removed | High priority alert |
| Dictionary changes | Zombie reference | CRITICAL alert |
| OUC state | New proposal submitted | Notify auditors |
| OUC state | Voting deadline approaching | Reminder |
| Auditor pool | Below threshold | Warning |
| Auditor pool | Auditor slashed | Investigation |

**Health States (Governance-by-Observation):**

| State | Description | FR Mapping |
|-------|-------------|------------|
| `Healthy` | Normal operation | All checks pass |
| `Wounded` | Minor anomaly, auto-recovery | f_env issues |
| `Drifting` | Local vs deployed divergence | DriftDetected |
| `Frozen` | Awaiting human decision | f_audit, f_liveness |
| `Dead` | Unrecoverable | f_key compromise |

**Urgency Levels:**

| Urgency | Trigger | Action |
|---------|---------|--------|
| `Immediate` | Frozen (AuditFailed) | Stop, human review |
| `Soon` | Drifting, Frozen | Handle in next batch |
| `Routine` | Wounded, Healthy | Normal cycle |
| `Archive` | Dead | Record only |

**Quarantine Rules:**

| Rule | Trigger | Action |
|------|---------|--------|
| `key-compromise` | KeyCompromise | Freeze + immediate review |
| `audit-failed` | AuditFailed | Freeze + block upgrade |
| `liveness-failing` | LivenessFailing | Freeze + block operations |
| `high-drift` | DriftDetected >= 100 lines | RequireMoreAuditors(2) |
| `repro-failure` | ReproFailure | RollbackPending |

**State Storage:**

```
.ouc-monitor/
├── config.json           # Monitoring configuration
├── health/
│   └── protocol-PROTOCOL_ID.json
├── snapshots/
│   ├── evm-YYYYMMDD-HHMMSS.json
│   └── icp-YYYYMMDD-HHMMSS.json
├── alerts/
│   └── alert-TIMESTAMP.json
└── logs/
    └── monitor-YYYYMMDD.log
```

---

## 3. Commands

### 3.1 /check-upgrade

**Location:** `.claude/commands/check-upgrade.md`

**Purpose:** Detect pending ERC-7546 upgrades by comparing Dictionary state.

**Arguments:**
- `$1`: Dictionary contract address (optional)
- `$2`: RPC URL (optional)

**Output Format:**

```
=== Upgrade Status Report ===
Dictionary: 0x...
Owner: 0x...
Block: 12345678

Selectors:
  0x12345678: MATCH (0x... -> 0x...)
  0xabcdef01: MISMATCH (expected 0x..., got 0x...)
  0xdeadbeef: MISSING (not deployed)

Risk Level: [CRITICAL|HIGH|MEDIUM|LOW|NONE]
Recommended Auditors: N
```

**Usage:**

```bash
/check-upgrade 0x1234...abcd https://mainnet.infura.io/v3/...

# Or with environment variables
export DICTIONARY_ADDR=0x1234...abcd
/check-upgrade
```

---

### 3.2 /propose-upgrade

**Location:** `.claude/commands/propose-upgrade.md`

**Purpose:** Generate and submit upgrade proposals to OUC canister.

**Arguments:**
- `$ARGUMENTS`: Proposal description
- `--dry-run`: Generate without submitting

**Workflow:**

1. Analyze current state with `lazy evm-lifecycle ask`
2. Generate structured proposal JSON
3. Assess risk based on change types
4. Submit to OUC (unless --dry-run)

**Risk Assessment:**

| Change Type | Count | Risk Level |
|-------------|-------|------------|
| Zombie Reference | Any | CRITICAL |
| Core Function Changed | >= 3 | HIGH |
| Core Function Changed | 1-2 | MEDIUM |
| Config Function Changed | Any | LOW |
| No Changes | - | NONE |

**Proposal Schema:**

```json
{
  "title": "Upgrade: [summary]",
  "description": "[detailed description]",
  "changes": [
    {
      "selector": "0x12345678",
      "function": "transfer(address,uint256)",
      "changeType": "CHANGED",
      "oldImpl": "0x...",
      "newImpl": "0x...",
      "rationale": "[why]"
    }
  ],
  "riskLevel": "MEDIUM",
  "recommendedAuditors": 2,
  "evidence": {
    "blockNumber": 12345678,
    "timestamp": "2025-01-10T00:00:00Z",
    "txHash": "0x..."
  }
}
```

**Usage:**

```bash
/propose-upgrade "Gas optimization for transfer function" --dry-run
```

---

## 4. Integration with lazy CLI

Both skills integrate with the `lazy` CLI tools:

| Command | Purpose |
|---------|---------|
| `lazy evm ask` | EVM contract STI Parity analysis |
| `lazy evm-lifecycle ask` | ERC-7546 upgrade detection |
| `lazy dfx ask` | ICP canister analysis |
| `lazy dfx-lifecycle ask` | Canister upgrade detection |

**Analysis Steps:**

```bash
# Full EVM analysis
lazy evm-lifecycle ask . --steps=1,2,3

# Full ICP analysis
lazy dfx ask . --steps=1,2,3,4
```

---

## 5. Monitoring Loop

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  AI Agent Monitoring Loop                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Fetch Current State                                                      │
│     ├── EVM: Dictionary implementations (ouc-onchain)                       │
│     ├── ICP: OUC canister state (ouc-onchain)                              │
│     └── Store snapshot (.ouc-monitor/snapshots/)                            │
│                                                                             │
│  2. Compare with Baseline                                                    │
│     ├── Load previous snapshot                                              │
│     ├── Detect changes (/check-upgrade)                                     │
│     └── Classify by severity (ouc-monitor)                                  │
│                                                                             │
│  3. Generate Actions                                                         │
│     ├── CRITICAL → Human alert + halt                                       │
│     ├── HIGH → Auto-propose (/propose-upgrade)                              │
│     ├── MEDIUM → Queue for review                                           │
│     └── LOW/INFO → Log                                                       │
│                                                                             │
│  4. Execute Actions                                                          │
│     ├── Submit proposals                                                     │
│     ├── Send notifications                                                   │
│     └── Update baseline                                                      │
│                                                                             │
│  5. Wait for next interval (cron: */5 * * * *)                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Future: Futarchy Integration

**Planned Capability:** `ouc-futarchy` skill

| Function | Description |
|----------|-------------|
| `getMarketPrice(proposalId)` | Query YES/NO prices for proposal |
| `getExpectedValue(proposalId)` | Market-derived expected outcome |
| `getMarketConfidence(proposalId)` | Trading volume indicator |

**Integration Point:**

```
Proposal Submitted
    │
    ▼
Create Prediction Market
    │
    ▼
Trading Period (7 days)
    │
    ▼
If expectedValue > threshold:
    → Proceed to /propose-upgrade
Else:
    → Skip (market pessimistic)
```

---

## 7. File Structure

```
.claude/
├── skills/
│   ├── ouc-onchain/
│   │   └── SKILL.md          # On-chain query patterns
│   ├── ouc-monitor/
│   │   └── SKILL.md          # Monitoring loop patterns
│   └── ouc-futarchy/         # (Future)
│       └── SKILL.md
└── commands/
    ├── check-upgrade.md      # /check-upgrade command
    └── propose-upgrade.md    # /propose-upgrade command
```

---

## 8. Usage Examples

### Example 1: Check for Upgrades

```
User: Check if there are any pending upgrades on mainnet

Claude: [Uses ouc-onchain skill to query Dictionary]
        [Executes /check-upgrade with mainnet RPC]
        [Reports findings with risk assessment]
```

### Example 2: Automated Monitoring

```
User: Set up monitoring for OUC

Claude: [Uses ouc-monitor skill patterns]
        [Creates .ouc-monitor/ directory structure]
        [Sets up cron job for periodic checks]
        [Configures alert thresholds]
```

### Example 3: Submit Proposal

```
User: The transfer function needs a gas optimization. Create a proposal.

Claude: [Uses /check-upgrade to detect current state]
        [Generates proposal with risk assessment]
        [Uses /propose-upgrade --dry-run for preview]
        [On confirmation, submits to OUC]
```

---

## References

- [FABI.md](./FABI.md) - Build Infrastructure
- [OUC-Spec.md](./OUC-Spec.md) - OUC Specification
- [Auditor-Workflow.md](./Auditor-Workflow.md) - Auditor Flow
- [Governance/Core.idr](../src/Governance/Core.idr) - Health States
