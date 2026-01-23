# OUC Dashboard 統合: 課題解決ツリー

## 目標

```
idris2-ouc-ui (Browser) → OUC Canister → SQLite → EVM Events
```

UI から OUC の SQLite に繋がるクエリが呼べる状態にする。

---

## 課題解決ツリー

```
目標: UI から OUC Canister 経由で Indexed Events を取得
│
├── [1] OUC Canister 側 (idris2-ouc)
│   │
│   ├── [1.1] SQLite 初期化 ✅ (icp-indexer/StorageSql.idr 存在)
│   │   ├── initSqlBackend : IO (StorageResult SqlBackendState)
│   │   ├── sqlStoreEvent : IndexedEvent -> IO (StorageResult Nat)
│   │   └── sqlQueryEvents : EventFilter -> ... -> IO (StorageResult EventPage)
│   │
│   ├── [1.2] OucIndexerAdapter 型定義 ✅ (今回作成)
│   │   ├── OUC イベント署名 (UpgradeProposed, VoteCast, etc.)
│   │   ├── OucEvent 型
│   │   ├── getUpgradeProposedEvents
│   │   ├── getVotesForProposal
│   │   └── getRecentOucEvents
│   │
│   ├── [1.3] Main.idr に Candid エンドポイント追加 ❌ TODO
│   │   │
│   │   ├── [1.3.1] IndexerState 初期化
│   │   │   ├── canister_init で initSqlBackend 呼び出し
│   │   │   └── グローバル SqlBackendState 保持
│   │   │
│   │   ├── [1.3.2] Query エンドポイント (新規コマンド追加)
│   │   │   ├── CMD 30: getOucEvents(filter) → JSON
│   │   │   ├── CMD 31: getProposalEvents(proposalId) → JSON
│   │   │   ├── CMD 32: getAuditorEvents(auditorAddr) → JSON
│   │   │   └── CMD 33: getDashboardSummary() → JSON
│   │   │
│   │   └── [1.3.3] Candid レスポンス構築
│   │       ├── eventToJson / pageToJson (icp-indexer/Query.idr 流用)
│   │       └── ic0_msg_reply_data_append でレスポンス返却
│   │
│   ├── [1.4] EVM Polling 統合 ❌ TODO (後回し可)
│   │   ├── Timer で定期 HTTP Outcall
│   │   ├── eth_getLogs → parse → sqlStoreEvent
│   │   └── ChainConfig, ContractConfig 設定
│   │
│   └── [1.5] Candid Interface (.did) 更新 ❌ TODO
│       └── getOucEvents, getDashboardSummary 等を追加
│
├── [2] Dashboard UI 側 (idris2-ouc-ui)
│   │
│   ├── [2.1] Indexer.idr FFI 更新 ❌ TODO
│   │   │   現状: window.oucIndexer.fetchEvents() (JS ブリッジ)
│   │   │   変更: OUC Canister を直接呼ぶ
│   │   │
│   │   ├── [2.1.1] @dfinity/agent 統合
│   │   │   └── src/indexer.js に HttpAgent + Actor 追加
│   │   │
│   │   └── [2.1.2] Candid 呼び出し
│   │       ├── actor.getOucEvents(filter)
│   │       ├── actor.getDashboardSummary()
│   │       └── Promise → Idris2 FFI 経由で Model 更新
│   │
│   ├── [2.2] Model.idr 型整合 ⚠️ 部分完了
│   │   ├── Auditor, OU, Proposal, Event 型は定義済み
│   │   └── OUC Candid レスポンスとのマッピング追加
│   │
│   └── [2.3] View.idr イベント表示 ✅ 完了
│       └── viewEventList, viewProposalCard 等は実装済み
│
└── [3] ビルド・デプロイ
    │
    ├── [3.1] OUC Canister ビルド
    │   ├── pack build ouc.ipkg
    │   ├── emcc → WASM
    │   └── dfx deploy ouc
    │
    └── [3.2] UI ビルド・デプロイ
        ├── npm run build
        └── dfx deploy ouc_dashboard
```

---

## 依存関係

```
[1.3] Main.idr エンドポイント
    ↓ depends on
[1.2] OucIndexerAdapter ✅
    ↓ depends on
[1.1] StorageSql ✅ (icp-indexer 内)

[2.1] UI Indexer.idr
    ↓ calls
[1.3] OUC Candid エンドポイント ❌
    ↓ uses
[1.5] .did ファイル ❌
```

---

## 優先度別タスク

### P0: 最小動作確認 (UI → OUC → 固定データ返却)

| # | タスク | ファイル | 状態 |
|---|--------|----------|------|
| 1 | Main.idr に getOucEvents コマンド追加 | idris2-ouc/src/Main.idr | ❌ |
| 2 | 固定 JSON レスポンス返却 (SQLite 未使用) | idris2-ouc/src/Main.idr | ❌ |
| 3 | ouc.did に getOucEvents 追加 | idris2-ouc/ouc.did | ❌ |
| 4 | indexer.js に Candid Actor 追加 | idris2-ouc-ui/src/indexer.js | ❌ |
| 5 | E2E 動作確認 | - | ❌ |

### P1: SQLite 接続

| # | タスク | ファイル | 状態 |
|---|--------|----------|------|
| 6 | canister_init で initSqlBackend | idris2-ouc/src/Main.idr | ❌ |
| 7 | getOucEvents で sqlQueryEvents 呼び出し | idris2-ouc/src/Main.idr | ❌ |
| 8 | OucIndexerAdapter で SQLite 層を使用 | idris2-ouc/src/Indexer/OucIndexerAdapter.idr | ❌ |

### P2: EVM Polling (実データ取得)

| # | タスク | ファイル | 状態 |
|---|--------|----------|------|
| 9 | Timer 設定 (ic0_timer) | idris2-ouc/src/Main.idr | ❌ |
| 10 | HTTP Outcall で eth_getLogs | idris2-ouc/src/HttpOutcall/*.idr | ⚠️ 部分 |
| 11 | ログパース → sqlStoreEvent | idris2-ouc/src/Indexer/OucIndexerAdapter.idr | ❌ |

---

## 現在地 (2026-01-24 更新)

```
[1.1] SQLite 初期化        ✅ icp-indexer の StorageSql.idr を使用
[1.2] OucIndexerAdapter    ✅ 型定義完了、typecheck 通過
[1.3] Main.idr エンドポイント ✅ CMD 30-33 追加済み + C エントリ追加
[1.4] EVM Polling          ✅ fetchEvmLogs 実装完了
[1.5] .did 更新            ✅ can.did 更新済み
[1.6] canister_entry.c     ✅ C エントリポイント追加 + eth_getLogs パース
[1.7] SQLite API 呼び出し   ✅ Idris2 側で StorageSql を import/使用
[1.8] SQLite C リンク       ✅ build-canister.sh で icp-indexer の SQLite WASI 統合
[1.9] 永続化 (stable memory) ✅ sqlite_stable_save/load で upgrade 跨ぎ永続化
[2.1] UI indexer.js        ✅ Candid Actor + 新API追加
[2.2] Model 型整合         ⚠️
[2.3] View                 ✅
[2.4] UI 統合テスト         ✅ @dfinity/agent から Candid 呼び出し成功
```

### 完了した作業

1. **Main.idr** - 4つの新コマンド追加
   - `CMD 30: getOucEvents(limit)` → イベント数を返す
   - `CMD 31: getProposalEvents(proposalId)` → 提案の投票イベント数
   - `CMD 32: getDashboardSummary()` → 総イベント数
   - `CMD 33: storeTestEvent(blockNum, eventType)` → テストイベント追加

2. **can.did** - Candid インターフェース更新
   - `getOucEvents`, `getProposalEvents`, `getDashboardSummary`, `storeTestEvent`

3. **indexer.js** - Candid Actor 統合
   - `@dfinity/agent` を使った OUC canister 直接呼び出し
   - `fetchOucEventsCount`, `fetchDashboardSummaryFromOuc`, etc.

4. **canister_entry.c** - C エントリポイント追加
   - `canister_query getOucEvents` / `getProposalEvents` / `getDashboardSummary`
   - `canister_update storeTestEvent`

5. **E2E 動作確認 (P0)** ✅ 完了
   ```bash
   # デプロイ成功
   dfx deploy ouc --network local
   # canister ID: uqqxf-5h777-77774-qaaaa-cai

   # テスト結果
   dfx canister call ouc getDashboardSummary '()' → (0 : nat) ✅
   dfx canister call ouc getOucEvents '(10 : nat)' → (0 : nat) ✅
   dfx canister call ouc storeTestEvent '(100 : nat, 0 : nat)' → (1 : nat) ✅
   ```

6. **P1: SQLite API 統合 (Idris2 側)** ✅ 完了
   - `Main.idr` に `StorageSql` と `StorageApi` をインポート
   - `initGlobalState` で `SqlStorage.initSqlBackend` を呼び出し
   - `doGetDashboardSummary` 等で `sqlGetStorageInfo` / `sqlQueryEvents` を使用
   - `doStoreTestEvent` で `sqlStoreEvent` を呼び出し

### 完了タスク一覧

**P0: E2E 動作確認** ✅ 完了
```bash
dfx canister call ouc getDashboardSummary '()' → (8 : nat) ✅
dfx canister call ouc storeTestEvent '(100, 0)' → (9 : nat) ✅
```

**P1: SQLite 接続 (状態永続化)** ✅ 完了
```
[x] canister_init で initSqlBackend 呼び出し
[x] IndexerStorage → StorageSql に切り替え
[x] SQLite C ライブラリを RefC パイプラインにリンク
    - libsqlite3.a (SQLite WASI prebuilt)
    - sqlite_bridge.c (Idris2 FFI ブリッジ)
    - sqlite_stable.c (stable memory 永続化)
    - wasi_polyfill.c (POSIX stubs)
[x] pre_upgrade/post_upgrade で stable memory 保存/復元
```

**P3: 永続化テスト** ✅ 完了
```bash
# テスト結果
dfx canister call ouc storeTestEvent '(1, 0)' → (1 : nat)
dfx canister call ouc storeTestEvent '(2, 1)' → (2 : nat)
dfx canister call ouc storeTestEvent '(3, 2)' → (3 : nat)
dfx deploy ouc --upgrade-unchanged  # upgrade
dfx canister call ouc getDashboardSummary '()' → (3 : nat)  # データ保持 ✅
```

**P4: EVM Polling (HTTP Outcall)** ✅ 完了
```
[x] fetchEvmLogs エンドポイント追加
[x] eth_getLogs JSON-RPC 構築
[x] EVM RPC canister 呼び出し
[x] レスポンスパース → SQLite 格納
```

### 残タスク

**UI 統合テスト** ✅ 完了
```bash
# Node.js から @dfinity/agent 経由で OUC Canister 呼び出し成功
node test-ouc-api.mjs
# getDashboardSummary(): 9
# getOucEvents(10): 9
# storeTestEvent(999, 1): 10
# ✅ All API tests passed!
```

**IC Mainnet デプロイ** (残タスク)
```
[ ] cycles 確保
[ ] dfx deploy --network ic
[ ] EVM RPC canister 経由で実イベント取得
```

### パフォーマンス

| 項目 | 値 |
|------|-----|
| WASM サイズ | 1.38 MB |
| ランタイムメモリ | 270 MB |
| Query レイテンシ | ~250ms |
| Update レイテンシ | ~1.2s |
