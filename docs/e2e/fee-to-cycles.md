# Fee-to-Cycles E2E Test

## Status: PASS (Type-Level)

12/12 tests passing as of 2025-01-14.

## Test Coverage

| Test ID | Description | Status |
|---------|-------------|--------|
| E2E_001 | ckETH deposit splits 70/30 | PASS |
| E2E_002 | Add cycles to operating reserve | PASS |
| E2E_003 | Reserve cycles succeeds | PASS |
| E2E_004 | Reserve cycles fails (insufficient) | PASS |
| E2E_005 | Minting request with slippage | PASS |
| E2E_006 | State machine advances | PASS |
| E2E_007 | Calculate cycles from ICP | PASS |
| E2E_008 | Registry add/find | PASS |
| E2E_009 | Registry totals on completion | PASS |
| E2E_010 | Full fee-to-cycles flow | PASS |
| E2E_011 | Profit distribution | PASS |
| E2E_012 | Treasury refill trigger | PASS |

## Flow Tested

```
ckETH deposit (1000)
    ↓
Treasury split (70% ops, 30% profit)
    ↓
Create MintingRequest (700 → 140 ICP)
    ↓
State machine: Pending → SwapInitiated → SwapCompleted → ... → Completed
    ↓
Add cycles to OperatingReserve (1400)
    ↓
Profit distribution to stakeholders
```

## What's NOT Tested

- Actual ICRC-1 transfer (mock values)
- Actual DEX swap (mock quote)
- Actual CMC mint (mock result)
- Network latency/errors

## Next: Real Integration

To move from type-level to real E2E:

1. Deploy to Mainnet with cycles
2. Receive real ckETH via ICRC-1
3. Call real DEX (ICPSwap/Sonic)
4. Call real CMC notify_top_up

See [cketh-bridge.md](./cketh-bridge.md) for ckETH integration status.

## Run Tests

```bash
pack build ouc.ipkg && ./build/exec/run-tests
```

## Source Files

- `src/Economics/Treasury.idr`
- `src/Economics/CyclesMinting.idr`
- `src/Economics/Tests/FeeToCyclesE2E.idr`
