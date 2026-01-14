# Fee-to-Cycles Conversion Flow

A-Life Economics: ETH fees collected on EVM → Cycles on ICP

## Overview

```
[EVM: ETH deposit]
        ↓
[ckETH on ICP]
        ↓
[Treasury: 70%/30% split]
        ↓ (70%)
[DEX: ckETH → ICP swap]
        ↓
[CMC: ICP → Cycles mint]
        ↓
[Operating Reserve: Available cycles]
```

## Modules

| Module | Purpose |
|--------|---------|
| `Economics.Treasury` | State management, pool accounting |
| `Economics.CyclesMinting` | DEX swap + CMC minting state machine |
| `Economics.Tier` | Service tier definitions |
| `Economics.ProtocolAccount` | Protocol account management |
| `Economics.Scheduler` | Daily deductions, heartbeat |

## Treasury Structure

```idris
record Treasury where
  ckEthBalance  : Nat           -- Total ckETH held
  operating     : OperatingReserve  -- Cycles for operations
  profit        : ProfitPool        -- For stakeholder distribution
  watermarks    : WatermarkConfig   -- Low/high refill triggers
```

### Deposit Split (70/30)
- **70%** → Operating Reserve (converted to cycles)
- **30%** → Profit Pool (distributed to stakeholders)

## Minting State Machine

```
MintingPending
    ↓ (initiate swap)
SwapInitiated(swapId)
    ↓ (swap completes)
SwapCompleted(icpAmount, block)
    ↓ (transfer to CMC subaccount)
TransferToSubaccount(amount)
    ↓ (call notify_top_up)
NotifyingCMC(blockHeight)
    ↓ (success)
MintingCompleted(cycles)

    or ↓ (failure)
MintingFailed(reason)
```

## Key Canisters

| Canister | ID | Purpose |
|----------|------|---------|
| CMC | `rkp4c-7iaaa-aaaaa-aaaca-cai` | Cycles Minting |
| ICP Ledger | `ryjl3-tyaaa-aaaaa-aaaba-cai` | ICP transfers |
| ckETH Ledger | `ss2fx-dyaaa-aaaar-qacoq-cai` | ckETH (ICRC-1) |

## E2E Tests (12 tests)

| Test | Description |
|------|-------------|
| E2E_001 | ckETH deposit splits 70/30 |
| E2E_002 | Add cycles to operating reserve |
| E2E_003 | Reserve cycles succeeds |
| E2E_004 | Reserve cycles fails (insufficient) |
| E2E_005 | Minting request with slippage |
| E2E_006 | State machine advances |
| E2E_007 | Calculate cycles from ICP |
| E2E_008 | Registry add/find |
| E2E_009 | Registry totals on completion |
| E2E_010 | Full fee-to-cycles flow |
| E2E_011 | Profit distribution |
| E2E_012 | Treasury refill trigger |

## Numeric Type Architecture

### Current State
- `idris2-ouc`: Uses `Nat` (Peano numbers, slow for large values)
- Tests use small values (1000, 5000) to avoid slowness

### Target Architecture

| Layer | Package | Type | Notes |
|-------|---------|------|-------|
| EVM | idris2-yul | `Integer` | Arbitrary precision |
| IC | idris2-cdk | `Bits64` | Fixed 64-bit |
| ABI | EVM.ABI.Types | `ABIType` | Type descriptors |
| Candid | ICP.Candid.Types | `CNat64` | Candid Nat64 |

### Migration Path
1. Replace `Nat` with `Bits64` in Treasury/CyclesMinting
2. Add `TokenAmount` type alias with backend-specific instances
3. Import types from idris2-yul/idris2-cdk via Pack

## Usage

```bash
# Build
pack build ouc.ipkg

# Test
./build/exec/run-tests
```

## References

- [ICP CMC Interface](https://internetcomputer.org/docs/current/references/ic-interface-spec#ic-cmc)
- [ICRC-1 Standard](https://github.com/dfinity/ICRC-1)
- [ckETH](https://github.com/dfinity/ic/tree/master/rs/ethereum/cketh)
