# Full E2E Mainnet Test

## Status: Not Started

Depends on all P0-P2 components.

## Overview

Two independent E2E flows to test:

1. **Economics Flow**: ETH deposit → ckETH → Treasury → DEX → CMC → Cycles
2. **Upgrade Flow**: A-Life proposes → OUC assigns auditors → Auditors vote → Execute

## Prerequisites

All must pass before attempting:

- [x] Unit Tests (52/52)
- [x] Fee-to-Cycles Type Tests (12/12)
- [ ] HTTP Outcall → EVM RPC ([http-outcall.md](./http-outcall.md))
- [ ] Threshold ECDSA Sign ([threshold-ecdsa.md](./threshold-ecdsa.md))
- [ ] Auditor Assignment ([erc7546-upgrade.md](./erc7546-upgrade.md))
- [ ] ckETH Bridge Receive ([cketh-bridge.md](./cketh-bridge.md))

---

## E2E Flow 1: Economics (Fee-to-Cycles)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Economics E2E Sequence                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. [ETH]     User deposits ETH to ckETH Helper                 │
│                     │                                           │
│                     ▼                                           │
│  2. [Bridge]  ckETH Minter processes (~20 min)                  │
│                     │                                           │
│                     ▼                                           │
│  3. [ICP]     OUC receives ckETH via ICRC-1                     │
│                     │                                           │
│                     ▼                                           │
│  4. [ICP]     Treasury splits 70/30 (ops/profit)                │
│                     │                                           │
│                     ▼                                           │
│  5. [ICP]     DEX swap: ckETH → ICP                             │
│                     │                                           │
│                     ▼                                           │
│  6. [ICP]     CMC mint: ICP → Cycles                            │
│                     │                                           │
│                     ▼                                           │
│  7. [ICP]     OperatingReserve refilled                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Test Commands (Economics)

```bash
# 1. Deploy OUC with cycles
dfx deploy --network ic ouc --with-cycles 2000000000000

# 2. Deposit ETH (from separate terminal)
source .env
cast send $HELPER_CONTRACT "deposit(bytes32)" $PRINCIPAL_BYTES32 \
  --value 0.1ether --private-key $ETH_EOA_PRIVATE_KEY \
  --rpc-url https://eth.llamarpc.com

# 3. Monitor OUC state
watch -n 60 "dfx canister call --network ic ouc getTreasuryStatus"

# 4. Verify cycles received
dfx canister call --network ic ouc getOperatingReserve
```

### Success Criteria (Economics)

- [ ] ETH deposited to ckETH Helper
- [ ] ckETH received by OUC canister
- [ ] Treasury balance reflects deposit
- [ ] DEX swap executed (ckETH → ICP)
- [ ] CMC mint executed (ICP → Cycles)
- [ ] OperatingReserve increased

---

## E2E Flow 2: Upgrade Governance

```
┌─────────────────────────────────────────────────────────────────┐
│                    Upgrade E2E Sequence                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. [EVM]     A-Life proposes upgrade to OU Contract            │
│                     │                                           │
│                     ▼                                           │
│  2. [ICP]     OUC detects new proposal (HTTP Outcall)           │
│                     │                                           │
│                     ▼                                           │
│  3. [ICP]     OUC assigns auditors (t-ECDSA sign tx)            │
│                     │                                           │
│                     ▼                                           │
│  4. [ICP]     Auditors vote via OUC (II/Passkey)                │
│                     │                                           │
│                     ▼                                           │
│  5. [ICP→EVM] Threshold → OUC sends executeApproved             │
│                     │                                           │
│                     ▼                                           │
│  6. [EVM]     ERC-7546 Dictionary updated                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Test Commands (Upgrade)

```bash
# 1. A-Life proposes upgrade (external to OUC)
cast send $OU_CONTRACT "proposeUpgrade(address,bytes)" \
  $NEW_IMPL $CALLDATA --private-key $ALIFE_KEY

# 2. OUC detects proposal
dfx canister call --network ic ouc getPendingProposals

# 3. OUC assigns auditors
dfx canister call --network ic ouc assignAuditors \
  '(record { proposalId = 1; auditors = vec { "0x..."; "0x..." } })'

# 4. Auditors vote via OUC (each auditor, II/Passkey認証)
dfx canister call --network ic ouc vote \
  '(record { proposalId = 1; approve = true })'

# 5. Check threshold and execution (OUC sends tx automatically)
cast call $OU_CONTRACT "getProposal(uint256)" 1
cast call $DICTIONARY "getImplementation(bytes4)" $SELECTOR
```

### Success Criteria (Upgrade)

- [ ] A-Life proposal recorded on OU Contract
- [ ] OUC successfully detects proposal via HTTP Outcall
- [ ] OUC successfully assigns auditors (tx executed on EVM)
- [ ] Auditor votes recorded in OUC (via II/Passkey)
- [ ] Threshold reached → OUC sends executeApproved tx
- [ ] ERC-7546 Dictionary implementation updated

---

## Resource Requirements

| Resource | Amount | Notes |
|----------|--------|-------|
| ETH (Mainnet) | 0.1 ETH | For deposit + gas |
| ICP (Cycles) | ~2T cycles | For canister operations |
| Time | ~1 hour | Including bridge wait |

## Failure Recovery

| Flow | Step | Failure | Recovery |
|------|------|---------|----------|
| Economics | 2 | Bridge timeout | Check ckETH Minter status |
| Economics | 5 | DEX slippage | Retry with higher slippage |
| Economics | 6 | CMC error | Check ICP balance, retry |
| Upgrade | 3 | Signing failed | Check t-ECDSA key, cycles |
| Upgrade | 4 | Vote rejected | Check Principal is registered auditor |

## Monitoring

```bash
# OUC canister status
dfx canister status --network ic ouc

# Treasury balance
dfx canister call --network ic ouc getTreasuryStatus

# Cycles balance
dfx canister status --network ic ouc | grep "Cycles Balance"

# Pending proposals
dfx canister call --network ic ouc getPendingProposals
```

## Related

- [../Mainnet-E2E-Test.md](../Mainnet-E2E-Test.md) - Original procedure doc
- [fee-to-cycles.md](./fee-to-cycles.md) - Economics flow details
- [erc7546-upgrade.md](./erc7546-upgrade.md) - Upgrade flow details
