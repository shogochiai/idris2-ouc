# ERC7546 Upgrade E2E Test

## Status: Type Ready (Not Tested)

Implementation complete, awaiting HTTP Outcall integration.

## Actors

| Actor | Role in Upgrade |
|-------|-----------------|
| **A-Life** | Proposes upgrades to OU Contract |
| **OUC Canister** | Assigns auditors to proposals |
| **Auditors** | Vote approve/reject on OU Contract |
| **OU Contract** | Governance: stores proposals, counts votes, executes |
| **ERC-7546 Dictionary** | Target: stores function→implementation mappings |

## What's Ready

- `ERC7546.Detection` module with upgrade detection
- `ERC7546.Execution` module with upgrade execution
- ABI encoding for `getImplementation`, `setImplementation`
- Upgrade proposal types and state machine

## Scenario Coverage

### Scenario 2: Upgrade Proposal (A-Life proposes)

```
A-Life                                            OU Contract (EVM)
  │                                                    │
  │── proposeUpgrade(newImpl, calldata) ─────────────►│
  │                                                    │── store proposal
  │                                                    │── emit ProposalCreated(id)
  │◄── proposalId ─────────────────────────────────────│
```

A-Life submits upgrade proposals directly to OU Contract on EVM.
OUC is not involved in this step.

---

### Scenario 3: Auditor Assignment (OUC assigns)

```
OUC Canister                                      OU Contract (EVM)
  │                                                    │
  │── (detect new proposal via HTTP Outcall)           │
  │                                                    │
  │── assignAuditors(proposalId, [addr1, addr2, ...]) ►│
  │                                                    │── store assigned auditors
  │                                                    │── emit AuditorsAssigned
```

OUC assigns auditors to proposals. This requires:
1. HTTP Outcall to read new proposals
2. t-ECDSA to sign the assignAuditors tx
3. Submit tx to EVM

---

### Scenario 3b: Auditor Voting (via OUC)

```
Auditors (II/Passkey)                             OUC Canister
  │                                                    │
  │── review proposal off-chain                        │
  │   (code audit, security analysis)                  │
  │                                                    │
  │── vote(proposalId, approve) ─────────────────────►│
  │   (Candid call, Principal認証)                     │── verify Principal
  │                                                    │── record vote
  │                                                    │── threshold++ (internal)
  │                                                    │
  │  (repeat for each assigned auditor)                │
  │                                                    │
  │                                               (threshold達成時)
  │                                               OUC ──► OU Contract
  │                                                    │   t-ECDSA署名
  │                                                    │   executeApproved()
```

Auditors vote via OUC (II/Passkey認証). OUC sends final tx when threshold met.

---

### Scenario 4: Upgrade Execution

```
OU Contract (EVM)                                 ERC-7546 Dictionary
  │                                                    │
  │── (threshold reached)                              │
  │                                                    │
  │── setImplementation(selector, newImpl) ───────────►│
  │                                                    │── update mapping
  │                                                    │── emit ImplementationUpdated
```

When threshold is reached, OU Contract calls ERC-7546 Dictionary to update
the function→implementation mapping.

---

## OUC Canister Responsibilities

**OUC DOES:**
- Read EVM state via HTTP Outcall (proposal detection)
- Assign auditors to proposals (cross-chain tx)
- Sign transactions via t-ECDSA

**OUC does NOT:**
- Propose upgrades (A-Life does this)
- Vote on proposals (Auditors do this)
- Execute upgrades (OU Contract does this)

## Test Steps

### P0: HTTP Outcall (prerequisite)

```bash
# Deploy to Mainnet
dfx deploy --network ic ouc

# Test EVM read
dfx canister call --network ic ouc testEthBlockNumber
```

### P0: Auditor Assignment

```bash
# Assign auditors to a proposal
dfx canister call --network ic ouc assignAuditors \
  '(record {
    proposalId = 1;
    auditors = vec { "0x123..."; "0x456..." }
  })'
```

### P1: Read Proposal State

```bash
# Read proposal from OU Contract
dfx canister call --network ic ouc getProposal '(1)'
```

### P1: Read Dictionary Implementation

```bash
# Read current implementation from ERC-7546 Dictionary
dfx canister call --network ic ouc getImplementation \
  '("0x<dictionary_address>", "0x<selector>")'
```

## Success Criteria

- [ ] `testEthBlockNumber` returns valid block number (P0)
- [ ] `assignAuditors` successfully submits tx to EVM (P0)
- [ ] `getProposal` reads proposal state correctly (P1)
- [ ] `getImplementation` reads dictionary state correctly (P1)
- [ ] Full flow: proposal → assignment → votes → execution (P3)

## Blockers

1. **P0**: HTTP Outcall must work on Mainnet
2. **P0**: t-ECDSA must work on Mainnet (for signing assignAuditors tx)
3. **P1**: Need deployed OU Contract on testnet/mainnet
4. **P3**: Full integration with A-Life and Auditors

## Source Files

- `src/ERC7546/Detection.idr`
- `src/ERC7546/Execution.idr`
- `src/ERC7546/Types.idr`

## Related

- [http-outcall.md](./http-outcall.md) - HTTP Outcall testing
- [threshold-ecdsa.md](./threshold-ecdsa.md) - t-ECDSA testing
- [README.md](./README.md) - Full scenario overview
