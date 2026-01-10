---
name: ouc-monitor
description: >
  Use this skill when monitoring OUC system state for anomalies or changes.
  Detects upgrade events, auditor pool changes, proposal status, and triggers
  appropriate actions. Part of the Self-Amending Protocol AI Agent infrastructure.
allowed-tools: Bash,Read,Grep,WebFetch
---

# OUC Monitoring Skill

This skill provides patterns for continuous monitoring of the OUC ecosystem.

## Monitoring Targets

### 1. ERC-7546 Dictionary Changes

Monitor for implementation changes:
```bash
# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC_URL)

# Compare with last known state
# Store snapshots in .ouc-monitor/snapshots/
```

**Triggers**:
- New selector added → Log + potential proposal
- Selector implementation changed → Alert + propose audit
- Selector removed → High priority alert
- Zombie reference detected → CRITICAL alert

### 2. OUC Canister State

```bash
# Check proposal queue
dfx canister call ouc getProposalCount

# Check for pending proposals needing review
dfx canister call ouc getPendingProposals

# Check auditor pool health
dfx canister call ouc getAuditorCount
```

**Triggers**:
- New proposal submitted → Notify auditors
- Proposal voting deadline approaching → Reminder
- Auditor pool below threshold → Warning

### 3. Auditor Pool Health

```bash
# Get active auditor count
dfx canister call ouc getActiveAuditorCount

# Check for slashed auditors
dfx canister call ouc getSlashedAuditors
```

**Triggers**:
- Active auditors < minimum threshold → Critical
- Auditor slashed → Investigation required
- Average reputation declining → Warning

## Alert Levels

| Level | Description | Action |
|-------|-------------|--------|
| CRITICAL | System integrity at risk | Immediate human review |
| HIGH | Significant change detected | Automated proposal + notification |
| MEDIUM | Notable change | Log + daily summary |
| LOW | Minor change | Log only |
| INFO | Status update | Periodic report |

## Monitoring Loop Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Loop                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Fetch Current State                                     │
│     ├── EVM: Dictionary implementations                     │
│     ├── ICP: OUC canister state                            │
│     └── Store snapshot                                      │
│                                                             │
│  2. Compare with Baseline                                   │
│     ├── Load previous snapshot                             │
│     ├── Detect changes                                      │
│     └── Classify by severity                                │
│                                                             │
│  3. Generate Actions                                        │
│     ├── CRITICAL → Human alert + halt                      │
│     ├── HIGH → Auto-propose + notify                       │
│     ├── MEDIUM → Queue for review                          │
│     └── LOW/INFO → Log                                     │
│                                                             │
│  4. Execute Actions                                         │
│     ├── Submit proposals                                    │
│     ├── Send notifications                                  │
│     └── Update baseline                                     │
│                                                             │
│  5. Wait for next interval                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## State Storage

Store monitoring state in `.ouc-monitor/`:

```
.ouc-monitor/
├── config.json           # Monitoring configuration
├── snapshots/
│   ├── evm-YYYYMMDD-HHMMSS.json
│   └── icp-YYYYMMDD-HHMMSS.json
├── alerts/
│   └── alert-TIMESTAMP.json
└── logs/
    └── monitor-YYYYMMDD.log
```

## Integration with lazy CLI

Use lazy tools for analysis:
```bash
# EVM lifecycle analysis
lazy evm-lifecycle ask . --steps=1,2,3

# ICP canister analysis
lazy dfx ask . --steps=1,2,3,4
```

## Automation

For continuous monitoring, use cron or systemd:

```bash
# Cron: Every 5 minutes
*/5 * * * * /path/to/ouc-monitor.sh >> /var/log/ouc-monitor.log 2>&1

# Or use watch for development
watch -n 300 '/path/to/ouc-monitor.sh'
```

## Example Monitor Script

```bash
#!/bin/bash
# ouc-monitor.sh

set -e

MONITOR_DIR=".ouc-monitor"
mkdir -p "$MONITOR_DIR/snapshots" "$MONITOR_DIR/alerts" "$MONITOR_DIR/logs"

# Take EVM snapshot
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
lazy evm-lifecycle ask . --output-json > "$MONITOR_DIR/snapshots/evm-$TIMESTAMP.json"

# Compare with previous
PREV=$(ls -t "$MONITOR_DIR/snapshots/evm-*.json" 2>/dev/null | sed -n '2p')
if [ -n "$PREV" ]; then
  # Diff and alert logic here
  diff "$PREV" "$MONITOR_DIR/snapshots/evm-$TIMESTAMP.json" || true
fi

# Take ICP snapshot
dfx canister call ouc getStatus > "$MONITOR_DIR/snapshots/icp-$TIMESTAMP.json"

echo "[$(date)] Monitor cycle complete" >> "$MONITOR_DIR/logs/monitor-$(date +%Y%m%d).log"
```
