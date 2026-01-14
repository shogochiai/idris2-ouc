# Threshold ECDSA E2E Test

## Status: Type Ready (Not Tested)

FFI interface implemented, awaiting Mainnet test.

## What's Ready

- `ThresholdECDSA.Core` module with key derivation, signing
- `ThresholdECDSA.FFI` module with IC System API bindings
- Key derivation path structure
- Signature request/response types

## Test Target

```
OUC Canister
    ↓ (ecdsa_public_key)
IC t-ECDSA Subnet
    ↓
Public key for canister

OUC Canister
    ↓ (sign_with_ecdsa)
IC t-ECDSA Subnet
    ↓
ECDSA signature (r, s)
```

## Blockers

1. **Mainnet Only**: t-ECDSA not available on local replica
2. **Key Name**: Must use correct key name for Mainnet (`key_1`)
3. **Cycles Cost**: Signing costs cycles

## Test Steps

```bash
# 1. Deploy to Mainnet
dfx deploy --network ic ouc

# 2. Get public key
dfx canister call --network ic ouc getEcdsaPublicKey

# 3. Sign message
dfx canister call --network ic ouc signMessage '("test message")'
```

## Success Criteria

- [ ] `getEcdsaPublicKey` returns 33-byte compressed public key
- [ ] `signMessage` returns valid (r, s) signature
- [ ] Signature verifiable with returned public key

## Key Names

| Environment | Key Name |
|-------------|----------|
| Local (dfx 0.15+) | `dfx_test_key` |
| Mainnet | `key_1` |

## Source Files

- `src/ThresholdECDSA/Core.idr`
- `src/ThresholdECDSA/FFI.idr`
- `src/ThresholdECDSA/Tests/AllTests.idr`

## Related

- [erc7546-upgrade.md](./erc7546-upgrade.md) - Uses t-ECDSA for signing auditor assignment tx
