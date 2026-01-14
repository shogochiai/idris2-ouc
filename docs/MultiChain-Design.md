# Multi-Chain Support Design

## OU Registry (OUC によるマルチチェーン OU 管理)

---

## 1. Overview

OUC は複数チェーンに存在する OU (Optimistic Upgrader) を管理・監視する。

**重要**: Cross-Chain Upgrade Execution は不要。各 OU は独立して UpgradeProposal を受け、処理する。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  OUC vs OU Architecture                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         ┌─────────────────┐                                 │
│                         │  OUC Canister   │                                 │
│                         │  (ICP)          │                                 │
│                         │                 │                                 │
│                         │ • OU Registry   │                                 │
│                         │ • Auditor管理   │                                 │
│                         │ • Dashboard     │                                 │
│                         │ • Tx Relay      │                                 │
│                         └────────┬────────┘                                 │
│                                  │ 監視 / Auditor署名付きTx送信             │
│            ┌─────────────────────┼─────────────────────┐                   │
│            ▼                     ▼                     ▼                    │
│     ┌──────────┐          ┌──────────┐          ┌──────────┐              │
│     │ OU (ETH) │          │ OU (ARB) │          │ OU (Base)│              │
│     │ chainId=1│          │chainId=42161│       │chainId=8453│            │
│     └────┬─────┘          └────┬─────┘          └────┬─────┘              │
│          │                     │                     │                      │
│     UpgradeProposal       UpgradeProposal       UpgradeProposal            │
│     (独立して処理)         (独立して処理)         (独立して処理)            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Chain Registry

### 2.1 Types

```idris
-- MultiChain/Registry.idr

||| Supported chain configuration
public export
record ChainConfig where
  constructor MkChainConfig
  chainId         : ChainId
  name            : String
  rpcUrl          : String           -- Primary RPC endpoint
  rpcBackups      : List String      -- Fallback endpoints
  oufAddr         : EvmAddress       -- OptimisticUpgraderFactory
  dictionaryAddr  : EvmAddress       -- Shared Dictionary
  blockTime       : Nat              -- Average block time (ms)
  confirmations   : Nat              -- Required confirmations
  gasMultiplier   : Nat              -- Gas estimate multiplier (basis points)
  isActive        : Bool
  addedAt         : Nat

||| Chain registry state
public export
record ChainRegistry where
  constructor MkChainRegistry
  chains          : List ChainConfig
  defaultChain    : ChainId
  lastUpdated     : Nat
```

### 2.2 Supported Chains (Initial)

| Chain | Chain ID | Status |
|-------|----------|--------|
| Ethereum Mainnet | 1 | Priority |
| Arbitrum One | 42161 | Priority |
| Base | 8453 | Priority |
| Optimism | 10 | Planned |
| Polygon | 137 | Planned |
| Avalanche C-Chain | 43114 | Planned |

### 2.3 Registry Operations

```idris
-- MultiChain/Registry.idr

||| Add new chain to registry
public export
addChain :
  ChainRegistry ->
  ChainConfig ->
  ICPrincipal ->                  -- Admin
  FR ChainRegistry
addChain registry config admin = do
  requireAdmin admin
  -- Validate chain config
  validateRpcEndpoint config.rpcUrl
  -- Check for duplicates
  case find (\c => c.chainId == config.chainId) registry.chains of
    Just _ => fail Update "addChain" "Chain already registered"
                   (Conflict ("Chain " ++ show config.chainId))
    Nothing =>
      let updated = { chains := config :: registry.chains } registry
      in ok Update "addChain" ("Added chain " ++ config.name) updated

||| Get chain config
public export
getChain : ChainRegistry -> ChainId -> FR ChainConfig
getChain registry chainId =
  case find (\c => c.chainId == chainId) registry.chains of
    Just config => ok Query "getChain" (show chainId) config
    Nothing => notFound Query "getChain" ("Chain " ++ show chainId)

||| List active chains
public export
getActiveChains : ChainRegistry -> List ChainConfig
getActiveChains registry = filter (.isActive) registry.chains
```

---

## 3. OU Registration Management

### 3.1 OU Registry Entry

```idris
-- MultiChain/OURegistry.idr (概念)

||| Registered OU on a specific chain
public export
record RegisteredOU where
  constructor MkRegisteredOU
  ouId            : Nat
  chainId         : ChainId
  ouAddress       : EvmAddress       -- OU contract address
  dictionaryAddr  : EvmAddress       -- Shared Dictionary
  registeredAt    : Nat
  lastSyncAt      : Nat              -- Last state sync
  isActive        : Bool

||| OU state snapshot (from chain query)
public export
record OUStateSnapshot where
  constructor MkOUStateSnapshot
  ouId            : Nat
  proposalCount   : Nat
  pendingCount    : Nat
  auditorCount    : Nat
  queriedAt       : Nat
  blockNumber     : Nat
```

### 3.2 Auditor署名 + OUC リレー

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Auditor Signature Relay Pattern                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Auditor が EVM 署名を作成 (MetaMask 等)                                 │
│     message = keccak256(abi.encode(proposalId, approve, chainId, ouAddr))  │
│     signature = sign(message, auditorPrivateKey)                           │
│                                                                             │
│  2. OUC が署名を collect (Candid call で受信)                              │
│                                                                             │
│  3. OUC が閾値達成を確認 (n-of-m)                                          │
│                                                                             │
│  4. OUC が Threshold ECDSA で tx 署名                                       │
│     calldata = OU.submitAuditResult(proposalId, signatures[])              │
│                                                                             │
│  5. OU が ecrecover で Auditor 署名を検証                                   │
│                                                                             │
│  6. OU が登録済み Auditor か確認 → 閾値達成なら処理                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**NOTE**: Cross-Chain Execution Strategy は不要。各 OU が独立して UpgradeProposal を処理する。

---

## 4. RPC Management

### 4.1 Endpoint Selection

```idris
-- MultiChain/Rpc.idr

||| RPC health status
public export
record RpcHealth where
  constructor MkRpcHealth
  endpoint        : String
  lastSuccess     : Nat
  lastFailure     : Maybe Nat
  avgLatency      : Nat              -- Average latency (ms)
  successRate     : Nat              -- Success rate (basis points)

||| Select best RPC endpoint
public export
selectRpcEndpoint :
  ChainConfig ->
  List RpcHealth ->
  String
selectRpcEndpoint config healths =
  let healthy = filter (\h => h.successRate > 9500) healths  -- 95%+
      sorted = sortBy (\a, b => compare a.avgLatency b.avgLatency) healthy
  in case sorted of
    (best :: _) => best.endpoint
    [] => config.rpcUrl  -- Fallback to primary
```

### 4.2 Failover Logic

```idris
-- MultiChain/Rpc.idr

||| Execute with failover
public export
executeWithFailover :
  ChainConfig ->
  (String -> FR a) ->             -- RPC operation
  FR a
executeWithFailover config op = do
  -- Try primary
  result <- tryRpc config.rpcUrl op
  case result of
    Right value => pure value
    Left err =>
      -- Try backups
      tryBackups config.rpcBackups op err

  where
    tryBackups : List String -> (String -> FR a) -> Fail -> FR a
    tryBackups [] _ err = fail Query "executeWithFailover" "All RPCs failed" err
    tryBackups (url :: rest) op _ = do
      result <- tryRpc url op
      case result of
        Right value => pure value
        Left err => tryBackups rest op err
```

---

## 5. Chain-Specific Considerations

### 5.1 Gas Estimation

```idris
-- MultiChain/Gas.idr

||| Chain-specific gas configuration
public export
record GasConfig where
  constructor MkGasConfig
  baseGas         : Nat              -- Base gas for upgrade tx
  priorityFee     : Nat              -- Priority fee (L2s)
  maxFee          : Nat              -- Max fee cap
  multiplier      : Nat              -- Safety multiplier (basis points)

||| Get gas config for chain
public export
getGasConfig : ChainId -> GasConfig
getGasConfig chainId = case chainId.value of
  1     => MkGasConfig 200000 2000000000 100000000000 12000  -- Ethereum
  42161 => MkGasConfig 150000 100000000 1000000000 11000     -- Arbitrum
  8453  => MkGasConfig 150000 100000000 1000000000 11000     -- Base
  _     => MkGasConfig 200000 1000000000 50000000000 12000   -- Default
```

### 5.2 Confirmation Requirements

| Chain | Confirmations | Finality Time |
|-------|---------------|---------------|
| Ethereum | 12 | ~3 minutes |
| Arbitrum | 1 | ~15 seconds |
| Base | 1 | ~2 seconds |
| Optimism | 1 | ~2 seconds |

### 5.3 Chain-Specific Errors

```idris
-- MultiChain/Errors.idr

||| Chain-specific error handling
public export
data ChainError
  = RpcUnreachable String
  | GasEstimateFailed String
  | NonceConflict Nat Nat            -- expected, actual
  | ReorgDetected Nat                -- reorg depth
  | L2SequencerDown                  -- L2-specific
  | L1DataUnavailable                -- L2-specific (calldata)

||| Error recovery action
public export
recoverFromError : ChainError -> FR RecoveryAction
recoverFromError err = case err of
  RpcUnreachable _ => ok Query "recover" "Switch RPC" SwitchRpc
  GasEstimateFailed _ => ok Query "recover" "Increase gas" IncreaseGas
  NonceConflict _ _ => ok Query "recover" "Refresh nonce" RefreshNonce
  ReorgDetected depth =>
    if depth > 12
      then ok Query "recover" "Deep reorg, manual review" ManualReview
      else ok Query "recover" "Wait for stability" WaitAndRetry
  L2SequencerDown => ok Query "recover" "Wait for sequencer" WaitAndRetry
  L1DataUnavailable => ok Query "recover" "Wait for L1 batch" WaitAndRetry
```

---

## 6. Threshold ECDSA Integration

### 6.1 Chain-Specific Keys

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Threshold ECDSA Key Derivation                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Master Key (ICP vetKeys)                                                   │
│         │                                                                   │
│         ├── Derivation Path: m/44'/60'/0'/0/{chainId}                      │
│         │                                                                   │
│         ├── Chain 1 (Ethereum)                                             │
│         │   └── Address: 0x1234...                                         │
│         │                                                                   │
│         ├── Chain 42161 (Arbitrum)                                         │
│         │   └── Address: 0x1234... (same, derived)                         │
│         │                                                                   │
│         └── Chain 8453 (Base)                                              │
│             └── Address: 0x1234... (same, derived)                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Signing Flow

```idris
-- MultiChain/Signing.idr

||| Request threshold ECDSA signature
public export
signForChain :
  ChainId ->
  String ->                       -- Message hash
  FR String                       -- Signature
signForChain chainId msgHash = do
  -- Derive key path for chain
  let keyPath = deriveKeyPath chainId
  -- Request signature from ICP vetKeys
  sig <- ic0_vetkey_sign keyPath msgHash
  ok Update "signForChain"
     ("Signed for chain " ++ show chainId)
     sig

||| Derive BIP-44 path for chain
deriveKeyPath : ChainId -> String
deriveKeyPath chainId =
  "m/44'/60'/0'/0/" ++ show chainId.value
```

---

## 7. State Synchronization

### 7.1 Cross-Chain State

```idris
-- MultiChain/State.idr

||| Synchronized state across chains
public export
record CrossChainState where
  constructor MkCrossChainState
  registry        : ChainRegistry
  upgradeHistory  : List CrossChainUpgrade
  pendingUpgrades : List CrossChainUpgrade
  chainHealths    : List (ChainId, RpcHealth)
  lastSyncTime    : Nat

||| Sync state from all chains
public export
syncAllChains :
  CrossChainState ->
  FR CrossChainState
syncAllChains state = do
  -- Query each active chain
  let activeChains = getActiveChains state.registry
  healths <- traverse queryChainHealth activeChains
  ok Update "syncAllChains"
     ("Synced " ++ show (length activeChains) ++ " chains")
     ({ chainHealths := healths, lastSyncTime := now } state)
```

---

## 8. Implementation Phases

### Phase 1: Foundation (完了)

- [x] ChainRegistry types and storage
- [x] Chain configuration management (Ethereum, Arbitrum, Base)
- [x] SPEC.toml + Tests

### Phase 2: OU Registry (次)

- [ ] RegisteredOU types
- [ ] OUStateSnapshot types
- [ ] OU 登録・更新・削除操作

### Phase 3: Auditor Signature Relay

- [ ] Auditor 署名収集 (Candid API)
- [ ] 閾値確認ロジック
- [ ] OU への Tx 送信 (Threshold ECDSA)

### Phase 4: Dashboard

- [ ] OU 状態一覧取得
- [ ] Auditor ↔ OU 割当て表示
- [ ] Proposal 状態集約

### ~~削除: Cross-Chain Execution~~

- ~~Sequential/Parallel execution~~
- ~~Cross-chain state proofs~~

**理由**: 各 OU が独立して UpgradeProposal を処理するため不要

---

## 9. Module Structure

```
idris2-ouc/src/
└── MultiChain/
    ├── Registry.idr          # Chain configuration (完了)
    ├── OURegistry.idr        # OU 登録管理 (次)
    ├── AuditorRelay.idr      # Auditor 署名リレー
    ├── Dashboard.idr         # OU 状態集約
    ├── SPEC.toml             # (完了)
    └── Tests/AllTests.idr    # (完了)
```

---

## 10. References

- ICP Threshold ECDSA: https://internetcomputer.org/docs/current/developer-docs/integrations/t-ecdsa
- EIP-155 Chain IDs: https://chainlist.org
- L2 Beat (L2 comparison): https://l2beat.com
