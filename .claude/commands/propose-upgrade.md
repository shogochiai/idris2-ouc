---
description: Generate and submit an upgrade proposal to OUC canister
allowed-tools: Bash,Read,Grep,Edit
argument-hint: <description> [--dry-run]
---

# Generate Upgrade Proposal

Create an upgrade proposal based on detected changes and submit to OUC canister.

## Arguments

- `$ARGUMENTS`: Proposal description and options
- `--dry-run`: Generate proposal without submitting

## Workflow

### 1. Analyze Current State

Run upgrade detection to identify changes:
```bash
# Use lazy evm-lifecycle ask for analysis
lazy evm-lifecycle ask . --steps=1,2,3
```

### 2. Generate Proposal Content

Based on the analysis, create a structured proposal:

```json
{
  "title": "Upgrade: [summary of changes]",
  "description": "[detailed description]",
  "changes": [
    {
      "selector": "0x12345678",
      "function": "transfer(address,uint256)",
      "changeType": "CHANGED",
      "oldImpl": "0x...",
      "newImpl": "0x...",
      "rationale": "[why this change]"
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

### 3. Risk Assessment

Map detected changes to risk levels:

| Change Type | Count | Risk Level |
|-------------|-------|------------|
| Zombie Reference | Any | CRITICAL |
| Core Function Changed | >= 3 | HIGH |
| Core Function Changed | 1-2 | MEDIUM |
| Config Function Changed | Any | LOW |
| No Changes | - | NONE |

### 4. Submit to OUC (if not --dry-run)

```bash
dfx canister call ouc submitProposal "(\"$PROPOSAL_JSON\")"
```

## Output

```
=== Upgrade Proposal ===

Title: Upgrade: Update transfer implementation
Risk Level: MEDIUM
Recommended Auditors: 2

Changes:
  1. transfer(address,uint256) [0x12345678]
     CHANGED: 0xOLD... -> 0xNEW...
     Rationale: Gas optimization

Evidence:
  Block: 12345678
  Timestamp: 2025-01-10T00:00:00Z

[--dry-run] Proposal generated but not submitted.

OR

Submitted! Proposal ID: 42
```

## Integration with OUC

The proposal triggers the following flow:
1. `submitProposal` creates pending proposal
2. Auto-assignment selects auditors based on risk
3. Auditors review and vote
4. On approval, upgrade is committed

## Example

```
/propose-upgrade "Gas optimization for transfer function" --dry-run
```
