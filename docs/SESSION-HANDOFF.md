# Session Handoff - OUC Development

Last updated: 2026-01-13

## Current State

### Completed
- [x] A-Life Economics Phase 1: Tier system (`src/Economics/Tier.idr`)
- [x] A-Life Economics Phase 1: ProtocolAccount (`src/Economics/ProtocolAccount.idr`)
- [x] A-Life Economics Phase 2: Scheduler (`src/Economics/Scheduler.idr`)
- [x] Economics tests: 25/25 passing
- [x] Main.idr Heartbeat integration (CMD 20-23)
- [x] ICP funding for mainnet testing
- [x] HTTP Outcall Candid encoding (verified working on mainnet)
- [x] EVM RPC canister integration (verified working on mainnet)
- [x] Dashboard UI: HTTP endpoint `/api/status` and HTML dashboard
- [x] ERC-7546 Dictionary query (`queryDictionary` method)
- [x] Error handling: RPC error classification and retry hints
- [x] Production EVM monitoring: `registerMonitor` and `pollContract` methods
- [x] Multi-chain EVM monitoring (EthMainnet, Sepolia, Base, Arbitrum)
- [x] ERC-7546 E2E test on Base Mainnet (SimpleDictionary + getImplementation)

### Pending
- [ ] On-chain Multicall for true batch optimization (EVM RPC doesn't support batch JSON-RPC)

## WASM Coverage Infrastructure

**Status**: WORKING - ic-wasm profiling + High Impact Targets fully operational

**idris2-dfx-coverage library** (`/Users/bob/code/idris2-dfx-coverage`):
- 16 Idris2 modules for coverage analysis
- **NEW**: `WasmBranchParser.idr` - WASM branch analysis (br_if, br_table, if)
- **NEW**: High Impact Targets based on branch count (like idris2-evm-coverage)
- `getUncoveredHighImpact` - Identify high-priority untested functions
- `calculateCoveragePriorities` - Rank functions by branch count × coverage status

**Test output** (OUC WASM with profiling):
```
High Impact Targets (top 10):
  func[223]: 285 branches (93 instructions)
  func[235]: 270 branches (135 instructions)  [COVERED]
  func[230]: 166 branches (83 instructions)

UNCOVERED High Impact Targets:
  func[223]: 285 branches (UNCOVERED - priority 285)
  func[230]: 166 branches (UNCOVERED - priority 166)
  func[184]: 146 branches (UNCOVERED - priority 146)
```

**Build artifacts**:
- `build/ouc.wasm` - Has WASI imports + name section (for coverage)
- `build/ouc_stubbed.wasm` - WASI stubbed (for IC deploy)

**Key learnings**:
1. `-g2` flag in Emscripten adds WASM name section (function names)
2. WASI stubbing regex must handle `$__wasi_*` names (Emscripten format)
3. ic-wasm instrument requires stable memory pre-allocated in canister_init
4. `__get_profiling(idx)` requires the int32 index parameter (0 for first chunk)

**Requirements for profiling**:
1. **Stable memory**: Pre-allocate in canister_init: `ic0_stable64_grow(10)`
2. **Match page settings**: `--start-page 0 --page-limit 10` must match grow amount
3. **Update calls only**: Query calls cannot be profiled
4. **Toggle tracing**: Call `__toggle_tracing` before update calls

**Working coverage workflow**:
```bash
# 1. Build with WASI stubbing
./scripts/build-canister.sh

# 2. Instrument stubbed WASM
ic-wasm build/ouc_stubbed.wasm -o /tmp/ouc_profiled.wasm instrument --start-page 0 --page-limit 10

# 3. Deploy instrumented version
cp /tmp/ouc_profiled.wasm .dfx/local/canisters/ouc/ouc.wasm
dfx canister install ouc --mode reinstall --yes

# 4. Run profiling
dfx canister call ouc __toggle_tracing          # Enable tracing
dfx canister call ouc registerAuditor           # Run update calls
dfx canister call ouc __get_profiling '(0 : int32)'  # Get trace

# 5. Check cycle count
dfx canister call ouc __get_cycles
```

**Profiling data format**:
- Returns: `(vec { record { func_idx: int32; cycle_count: int64 }}, next_idx: opt int32)`
- Positive func_idx = function entry
- Negative func_idx = function exit
- Example: `{ 174; 74_872 }` = function 174 entered at cycle 74,872

**idris2-dfx-coverage library** (`/Users/bob/code/idris2-dfx-coverage`):
- 15 Idris2 modules for coverage analysis
- ic0_mock.wat for IC API mocking
- Instrumenter.idr wraps ic-wasm
- ProfilingParser.idr parses __get_profiling output

## EVM Contract Monitoring

The OUC canister monitors ERC-7546 Dictionary contracts across multiple chains.

**Supported Chains**:
| Chain | chainId |
|-------|---------|
| EthMainnet | 1 |
| EthSepolia | 11155111 |
| Base | 8453 |
| Arbitrum | 42161 |

**Methods**:
- `registerMonitor(dictionary: text, selector: text, chainId: nat32)` - Register a contract for monitoring
- `pollContract(contractIndex: nat32)` - Query implementation via `getImplementation(bytes4)`
- `getMonitoringStatus()` - Get current monitoring state

**Example** (SimpleDictionary on Base):
```bash
# Register ERC-7546 Dictionary on Base Mainnet
dfx canister call ouc registerMonitor '("0x8a013eeFC98E2a471b8B53A67acB0f6cD5e670Ad", "0x12345678", 8453 : nat32)' --network ic

# Poll the contract to get implementation
dfx canister call ouc pollContract '(0 : nat32)' --network ic
# Returns: {"batchResults":["0x000000000000000000000000deadbeef000000000000000000000000deadbeef"],"count":1,"contractIdx":0}
```

**Test Contract**:
- SimpleDictionary: `0x8a013eeFC98E2a471b8B53A67acB0f6cD5e670Ad` (Base Mainnet)
- Source: `tests/erc7546/SimpleDictionary.sol`

## Dashboard UI

The OUC canister now serves HTTP responses directly:

**Endpoints**:
- `/api/status` - JSON status (version, auditors, proposals, features)
- `/` or `/dashboard` - HTML dashboard

**Access**:
```
https://nrkou-hqaaa-aaaah-qq6qa-cai.raw.icp0.io/api/status
https://nrkou-hqaaa-aaaah-qq6qa-cai.raw.icp0.io/
```

**Key Candid HttpResponse encoding**:
- 4 types in type table (header tuple, vec nat8, vec header, HttpResponse record)
- Compound types (vec) must be defined in type table and referenced by index
- Field hashes: body=0x411b7aa2, headers=0x63085246, status_code=0xcf2c909a

## Error Handling

EVM RPC error responses now include:
- `errorType`: "rpc", "parse", "sys_fatal", "sys_transient", "canister_reject", etc.
- `retryable`: true/false flag for client-side retry logic

Retryable errors:
- IC reject code 2 (SysTransient)
- IC reject code 5 (CanisterError)
- RPC error codes -32603 (internal error), -32002 (resource unavailable)

Permanent errors:
- RPC error codes -32700 (parse), -32600 (invalid request), -32601 (method not found)

## HTTP Outcall Status

The HTTP Outcall FFI implementation is **working**:
- ✅ Candid encoding for HttpRequestArgs (GET and POST)
- ✅ Callback signatures (i32 env parameter for IC)
- ✅ nat64 encoding as 8-byte little-endian (not LEB128!)
- ✅ IC management canister calls successful

**Consensus Issue**: ICP HTTP outcalls require ALL replicas to receive byte-identical responses. Without a transform function, varying headers (Date, CF-RAY, etc.) cause consensus failure.

**Solution**: Use the **EVM RPC canister** (`7hfb6-caaaa-aaaar-qadga-cai`) which handles:
- HTTP outcall complexity
- Consensus / transform functions
- Multiple EVM chain support

**Verified working** (2026-01-13):
```
dfx canister call ouc testEvmRpc --network ic
# Response: {"jsonrpc":"2.0","id":1,"result":"0x17192c0"} (block 24,252,096)
```

### Key Candid Encoding Learnings

1. **Field hashes**: Use djb2-like algorithm: `h = (h * 223 + c) mod 2^32`
2. **nat64**: Encoded as 8 bytes little-endian, NOT LEB128
3. **nat/int**: Encoded as LEB128 (variable length)
4. **opt values**: 0x00 = None, 0x01 = Some
5. **Type table order**: Define compound types before referencing them
6. **Variant encoding**: Options sorted by hash, values encoded by sorted index
7. **Principal encoding**: Raw bytes without CRC32 checksum (e.g., EVM RPC: `00 00 00 00 02 30 00 cc 01 01`)

## Account Information

### dfx Identity (Development)
```
Principal: azyqv-vy3mt-jnfeq-acu5r-ntam3-xpvfv-zdwjl-6zlha-ec7aq-zxuyw-qqe
Account ID: 75ed1c9c91f6c5fb2987039cef418b19a5a8b179f66de8ecefde8f62c8868a99
```

### Balances (as of 2026-01-12)
- ICP: ~3 ICP
- Cycles: ~4.5T cycles

### Internet Identity (NNS)
```
Anchor: 2946646
Principal: yoma5-yaya3-vq7ht-gimiw-loieu-efexw-en2du-stxyz-xrdgy-toun3-aqe
Account ID: 25091be673b5eb11c86770d41e2326f3b83669716fb125ef2c0033b796875ce5
```

### OUC Canister (Mainnet)
```
Canister ID: nrkou-hqaaa-aaaah-qq6qa-cai
```

### ETH EOA (Temporary - for ckETH conversion)
```
Address: 0xd27DB17F47DA8A76Cd8977b7c86f8796a35E39C8
Private key: stored in .env (gitignored)
Remaining balance: ~0.005 ETH
```

## Key Files

| File | Description |
|------|-------------|
| `src/Main.idr` | Canister entry point with CMD dispatch |
| `src/Economics/*.idr` | A-Life economics modules |
| `lib/ic0/canister_entry.c` | C entry points, HTTP outcall, Candid encoding |
| `lib/ic0/ic0_stubs.c` | FFI bridge between C and Idris2 |
| `.env` | Contains ETH EOA private key (gitignored) |

## Commands Reference

```bash
# Build OUC canister WASM
./scripts/build-canister.sh

# Deploy to mainnet (requires dfx cache update)
cp build/ouc_stubbed.wasm .dfx/ic/canisters/ouc/ouc.wasm
dfx canister install ouc --network ic --mode reinstall --yes

# Test EVM RPC canister (recommended - handles consensus)
dfx canister call ouc testEvmRpc --network ic

# Test direct HTTP outcall (may fail due to consensus)
dfx canister call ouc testEthBlockNumber --network ic
dfx canister call ouc testHttpGet --network ic

# Run economics tests
./build/exec/econ-tests

# Check ICP balance
dfx ledger balance --network ic

# Check cycles balance
dfx cycles balance --network ic
```

## Notes

- dfx caches WASM in `.dfx/ic/canisters/ouc/ouc.wasm` - must copy there before deploy
- HTTP outcalls require ~20-30B cycles per request
- ckETH deposit takes ~20-30 minutes for ICP minter to process
- Internet Identity Passkeys are device/browser-bound
