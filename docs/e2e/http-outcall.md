# HTTP Outcall → EVM RPC E2E Test

## Status: Procedure Ready (Not Executed)

Test procedure documented in [../Mainnet-E2E-Test.md](../Mainnet-E2E-Test.md).

## What's Ready

- `HttpOutcall.Core` module implemented
- `HttpOutcall.EvmRpc` module with eth_blockNumber, eth_call, eth_sendRawTransaction
- FFI bridge to IC management canister
- JSON-RPC encoding/decoding

## Test Target

```
OUC Canister
    ↓ (http_request)
IC Management Canister
    ↓ (HTTPS)
EVM RPC Endpoint (eth.llamarpc.com)
    ↓
eth_blockNumber response
```

## Blockers

1. **Mainnet Cycles**: Need ~1T cycles for deploy + calls
2. **Local Replica Limitation**: HTTP Outcall requires Mainnet or special config

## Test Steps

```bash
# 1. Deploy to Mainnet
dfx deploy --network ic ouc

# 2. Call test method
dfx canister call --network ic ouc testEthBlockNumber

# Expected result
# {"status":"success","result":"0x1234567"}
```

## Success Criteria

- [ ] `testEthBlockNumber` returns valid hex block number
- [ ] No timeout (< 30s response)
- [ ] No HTTP 429 rate limit error

## Source Files

- `src/HttpOutcall/Core.idr`
- `src/HttpOutcall/EvmRpc.idr`
- `src/Candid/EvmRpc.idr`

## Related

- [mainnet.md](./mainnet.md) - Full Mainnet test procedure
