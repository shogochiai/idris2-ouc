# E2E Test Strategy

OUC の End-to-End テスト戦略。

## Actors

テストに関与するアクター:

| Actor | Role | Location |
|-------|------|----------|
| **User** | Deposits ETH for fees | External |
| **A-Life** | LLM Agent that proposes upgrades | External |
| **Auditors** | Review and approve upgrades | External |
| **OUC Canister** | Treasury, cycles, auditor assignment | ICP |
| **OU Contract** | Upgrade governance (proposals, votes, execution) | EVM |
| **ERC-7546 Dictionary** | Stores function→implementation mappings | EVM |
| **ckETH Minter** | ETH ↔ ckETH bridge | ICP |
| **DEX** | ckETH → ICP swap | ICP |
| **CMC** | ICP → Cycles mint | ICP |

## E2E Test Scenarios

### Scenario 1: Economics Flow (Fee-to-Cycles)

```
User                    ckETH Minter              OUC Canister
  │                          │                         │
  │── deposit ETH ──────────►│                         │
  │                          │── ICRC-1 transfer ─────►│
  │                          │                         │── Treasury.receive()
  │                          │                         │── 70/30 split
  │                          │                         │
  │                          │                    DEX  │
  │                          │                     │   │
  │                          │                     │◄──│── swap ckETH→ICP
  │                          │                     │───│──►
  │                          │                         │
  │                          │                    CMC  │
  │                          │                     │   │
  │                          │                     │◄──│── mint ICP→Cycles
  │                          │                     │───│──►
  │                          │                         │── OperatingReserve++
```

**Tests**: [fee-to-cycles.md](./fee-to-cycles.md), [cketh-bridge.md](./cketh-bridge.md)

---

### Scenario 2: Upgrade Proposal (A-Life proposes)

```
A-Life                                            OU Contract (EVM)
  │                                                    │
  │── proposeUpgrade(newImpl, ...) ───────────────────►│
  │                                                    │── store proposal
  │                                                    │── emit ProposalCreated
```

**Note**: A-Life submits proposals directly to OU Contract on EVM.

**Tests**: [erc7546-upgrade.md](./erc7546-upgrade.md)

---

### Scenario 3: Auditor Assignment & Voting

```
OUC Canister                                      OU Contract (EVM)
  │                                                    │
  │── assignAuditors(proposalId, [...]) ─────────────►│
  │                                                    │── store assigned auditors

Auditors (II/Passkey)                             OUC Canister
  │                                                    │
  │── review proposal off-chain                        │
  │                                                    │
  │── vote(proposalId, approve) ─────────────────────►│
  │   (Candid call, Principal認証)                     │── record vote
  │                                                    │── check threshold (n-of-m)
  │                                                    │
  │                                               (threshold達成時)
  │                                                    │
  │                                               OUC ──► OU Contract
  │                                                    │   t-ECDSA署名で
  │                                                    │   executeApproved()
```

**Note**: Auditors vote via OUC (II/Passkey). OUC sends final tx to EVM.

**Tests**: [erc7546-upgrade.md](./erc7546-upgrade.md)

---

### Scenario 4: Upgrade Execution (Threshold Reached)

```
OU Contract (EVM)                                 ERC-7546 Dictionary
  │                                                    │
  │── (threshold reached)                              │
  │                                                    │
  │── executeUpgrade() ───────────────────────────────►│
  │                                                    │── setImplementation(fn, impl)
  │                                                    │── emit ImplementationUpdated
```

**Note**: Execution is triggered through OU Contract, updates ERC-7546 Dictionary.

**Tests**: [erc7546-upgrade.md](./erc7546-upgrade.md)

---

### Scenario 5: Tier Economics (derived from docs/economics/)

経済モデル (docs/economics/ouc.md) から帰納されたテストシナリオ。

**注**: 型化・単体テストで十分なものは除外。外部依存がある真の E2E のみ記載。

#### E2E-ECON-004: Catch-up Sync 実行

```
User                    OUC Canister              External Indexer
  │                          │                         │
  │── catchupSync(days=30) ─►│                         │
  │                          │── cost = 30 * dailyRate │
  │                          │── balance -= cost       │
  │                          │── fetchHistory() ──────►│
  │                          │◄── history data ────────│
  │                          │── return SyncResult     │
```

**期待結果**: 指定日数分の履歴を取得、コスト計算正確
**外部依存**: External Indexer (HTTP Outcall)

#### E2E-ECON-006: Archive 状態での Cycles 枯渇

```
Timer                   OUC Canister
  │                          │
  │── dailyCheck() ─────────►│
  │                          │── balance: 0.01 ETH (Archive Tier)
  │                          │── cycles: 0 (枯渇)
  │                          │
  │                          │── canOperate() → false
  │                          │── emit CyclesDepleted
  │                          │── status = SUSPENDED
```

**期待結果**:
- ETH 残高があっても cycles 枯渇で運用停止
- SUSPENDED 状態では query のみ、update 不可

**外部依存**: ICP runtime (実際の cycles 消費)

#### E2E-ECON-007: Archive からの復帰フロー

```
User                    OUC Canister              External Indexer
  │                          │                         │
  │                          │── status: SUSPENDED     │
  │                          │── lastSyncBlock: 1000   │
  │                          │── currentBlock: 100000  │
  │                          │                         │
  │── donate(0.1 ETH) ──────►│                         │
  │                          │── status = RECOVERING   │
  │                          │                         │
  │                          │── startCatchUpSync() ──►│
  │                          │◄── batch 1..N ──────────│
  │                          │                         │
  │                          │── status = ACTIVE       │
```

**期待結果**:
- SUSPENDED → RECOVERING → ACTIVE の状態遷移
- 長期 Archive 後の大量ブロック同期

**外部依存**: External Indexer, ICP runtime

#### E2E-ECON-008: Cycles 補充フロー

```
OUC Canister                              DEX / CMC
  │                                           │
  │── cycles: LOW                             │
  │── balance: 0.05 ETH                       │
  │                                           │
  │── swap ETH→ICP ──────────────────────────►│
  │── mint ICP→Cycles ───────────────────────►│
  │◄── cycles ────────────────────────────────│
  │                                           │
  │── cycles: OK                              │
```

**期待結果**:
- 自動 cycles 補充トリガー (閾値ベース)
- ETH → cycles 変換完了

**外部依存**: DEX, CMC (ICP canisters)

**Tests**: [tier-economics.md](./tier-economics.md) (予定)

---

### 型化・単体テストで検証すべき項目 (E2E 不要)

以下は E2E ではなく、型レベル保証または単体テストで検証:

| ID | 項目 | 検証方法 | 実装先 |
|----|------|----------|--------|
| ECON-001 | Tier 計算 | **型** (依存型で閾値証明) | Economics/Tier.idr |
| ECON-002 | 寄付→昇格 | 単体 (状態遷移ロジック) | Economics/Donation.idr |
| ECON-003 | 自動降格 | 単体 (Timer mock) | Economics/TierManager.idr |
| ECON-005 | 年数計算 | **型** (算術的正しさ) | Economics/PerpetualArchive.idr |

詳細は [../ecosystem.md](../ecosystem.md) の課題解決ツリー参照。

---

## Status Summary

| Scenario | Component | Status | Doc |
|----------|-----------|--------|-----|
| Unit Tests | - | **PASS** (52/52) | - |
| Scenario 1 | Fee-to-Cycles (Type) | **PASS** (12/12) | [fee-to-cycles.md](./fee-to-cycles.md) |
| Scenario 1 | ckETH Bridge | Not Started | [cketh-bridge.md](./cketh-bridge.md) |
| Scenario 2 | HTTP Outcall | **PASS** (Mainnet) | [http-outcall.md](./http-outcall.md) |
| Scenario 2 | t-ECDSA Sign | Type Ready | [threshold-ecdsa.md](./threshold-ecdsa.md) |
| Scenario 4 | ERC7546 Upgrade | Type Ready | [erc7546-upgrade.md](./erc7546-upgrade.md) |
| Scenario 5 | Tier Economics | Not Started | [tier-economics.md](./tier-economics.md) |
| Full | Mainnet E2E | Not Started | [mainnet.md](./mainnet.md) |

## Test Priority

### P0: ICP Primitives

| # | Test | Actor | 期待結果 | Status |
|---|------|-------|---------|--------|
| 1 | HTTP Outcall → EVM RPC | OUC | Block number 取得 | ✅ PASS |
| 2 | Auditor Assignment | OUC → OU | assignAuditors() 成功 | Not Started |

### P1: Cross-Chain Communication

| # | Test | Actor | 期待結果 | Status |
|---|------|-------|---------|--------|
| 3 | EVM State Read | OUC → OU | Proposal state 取得 | Not Started |
| 4 | EVM Tx from ICP | OUC → OU | t-ECDSA 署名 tx 送信成功 | Not Started |

### P2: Economics Integration

| # | Test | Actor | 期待結果 | Status |
|---|------|-------|---------|--------|
| 5 | ckETH Bridge | ckETH → OUC | ICRC-1 transfer 受信 | Not Started |
| 6 | DEX + CMC | OUC → DEX → CMC | Cycles mint 成功 | Not Started |
| 7 | Catch-up Sync | OUC → Indexer | 履歴取得とコスト計算 | Not Started |
| 8 | Cycles Depletion | ICP runtime | cycles 枯渇で SUSPENDED | Not Started |
| 9 | Archive Recovery | OUC → Indexer | SUSPENDED → ACTIVE 復帰 | Not Started |
| 10 | Cycles Top-up | OUC → DEX → CMC | ETH → cycles 自動補充 | Not Started |

### P3: Full Integration

| # | Test | Actor | 期待結果 | Status |
|---|------|-------|---------|--------|
| 7 | Full E2E | All | ETH → Cycles → Upgrade 完了 | Not Started |

## Test Environments

| Environment | Scenarios Testable | Notes |
|-------------|-------------------|-------|
| Unit (`pack build`) | Type-level only | Fast, no network |
| Local ICP (`dfx start`) | Scenario 1 (partial) | No HTTP Outcall |
| Mainnet | All | Cycles required |

## Commands

```bash
# Unit tests
pack build ouc.ipkg && ./build/exec/run-tests

# Local ICP
dfx start --clean --background
dfx deploy ouc

# Mainnet
dfx deploy --network ic ouc
dfx canister call --network ic ouc testEthBlockNumber
```

## Related Docs

- [../Mainnet-E2E-Test.md](../Mainnet-E2E-Test.md) - Mainnet テスト手順
- [../FeeToCycles.md](../FeeToCycles.md) - Fee-to-Cycles フロー詳細
- [../ecosystem.md](../ecosystem.md) - 課題解決ツリー (開発ロードマップ)
- [../economics/ouc.md](../economics/ouc.md) - Tier 経済モデル (Scenario 5 の出典)
