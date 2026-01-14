# ckETH Bridge E2E Test

## Status: Not Started

ICRC-1 receive callback not yet implemented.

## What's Needed

- ICRC-1 transfer receive handler
- ckETH Minter canister ID configuration
- Balance verification logic

## Architecture

```
ETH (Ethereum)
    │
    └─── User deposits ETH to ckETH Helper contract
            │
            ▼
ckETH Minter (ICP)
    │
    └─── Mints ckETH, sends ICRC-1 transfer to OUC
            │
            ▼
OUC Canister
    │
    ├─── Receives ICRC-1 transfer notification
    │
    ├─── Credits Treasury.ckEthBalance
    │
    └─── Triggers fee-to-cycles flow
```

## Candid Interface (Target)

```candid
type TransferNotification = record {
  from : principal;
  amount : nat;
  memo : opt blob;
};

// OUC must implement this callback
icrc1_transfer_notification : (TransferNotification) -> ();
```

## Blockers

1. **ICRC-1 Callback**: Need to implement receive handler
2. **Minter Integration**: Configure ckETH Minter canister ID
3. **Testing**: Need testnet ckETH or Mainnet deployment

## Test Steps (Future)

```bash
# 1. Deploy OUC to Mainnet
dfx deploy --network ic ouc

# 2. Deposit ETH to ckETH Helper contract (from Ethereum)
cast send $HELPER_CONTRACT "deposit(bytes32)" $PRINCIPAL_BYTES32 \
  --value 0.01ether --private-key $KEY

# 3. Wait for ckETH Minter to process (~20 minutes)

# 4. Verify OUC received ckETH
dfx canister call --network ic ouc getTreasuryBalance
```

## Success Criteria

- [ ] OUC receives ICRC-1 transfer notification
- [ ] Treasury.ckEthBalance incremented correctly
- [ ] Fee-to-cycles flow triggered automatically

## Dependencies

| Component | Canister ID | Network |
|-----------|-------------|---------|
| ckETH Minter | `ss2fx-dyaaa-aaaar-qacoq-cai` | Mainnet |
| ckETH Ledger | `ss2fx-dyaaa-aaaar-qacoq-cai` | Mainnet |

## Source Files (To Create)

- `src/Bridge/CkEth.idr` - ckETH integration
- `src/Bridge/ICRC1.idr` - ICRC-1 transfer handling

## Related

- [fee-to-cycles.md](./fee-to-cycles.md) - Downstream flow after receiving ckETH
- [../NumericTypes.md](../NumericTypes.md) - Integer type for amounts
