# OUC Ecosystem Architecture

Self-Amending Protocol実現のためのエコシステム要素と残タスク。

```
OUC Ecosystem
│
├── lazy CLI (~/code/lazy)
│   │
│   ├── [x] lazy core ask          # Idris2 STI Parity分析
│   │
│   ├── EVM側
│   │   ├── [ ] lazy evm ask           # EVM契約分析（stub）
│   │   │   └── 依存: idris2-yul 分析機能
│   │   └── [~] lazy evm-lifecycle ask # デプロイ/Upgrade助言 (進行中 2025/01/10)
│   │       │   ※ mc (metacontract) パターン対応
│   │       │   Dictionary: selector → impl マッピング
│   │       │   Proxy: Dictionary委譲
│   │       │   Upgrade: Dictionaryエントリ変更
│   │       │   パッケージ: lazy/pkgs/LazyEvmLifecycle (ビルド成功)
│   │       ├── [x] Dictionary状態クエリ (selector→impl via cast call)
│   │       ├── [x] Storage slot読み取り (cast storage + hex parse)
│   │       ├── [x] Block number取得 (cast block-number)
│   │       ├── [x] Local vs Deployed impl比較 (2025/01/10)
│   │       │       └── Compare.compareLocalVsDeployed: handlers ↔ dictionary比較
│   │       ├── [x] Pending upgrade検出 (2025/01/10)
│   │       │       └── Upgrade.detectPendingUpgrades: snapshot間diff検出
│   │       ├── [x] idris2-subcontract連携準備 (ERC7546 UCS型参照)
│   │       └── [ ] Auditor割当て推奨
│   │
│   └── ICP側
│       ├── [x] lazy dfx ask           # Canister分析 (4/4 完了)
│       │   ├── [x] Candid interface検証 (--steps=4)
│       │   ├── [x] WASM code coverage (--steps=4, ic-wasm)
│       │   ├── [x] Cycle消費分析 (--steps=4, top consumers表示)
│       │   └── [x] HTTP Outcall依存検出 (--steps=4, ic0 call_* imports)
│       └── [x] lazy dfx-lifecycle ask # Canister lifecycle助言 (完了)
│           ├── [x] dfx deploy連携 (dfx canister status)
│           ├── [x] Canister upgrade検出 (local vs deployed hash)
│           ├── [x] Stable memory migration (pre/post upgrade hooks)
│           └── [x] Controller権限管理 (single/no controller警告)
│
│   NOTE: mc (metacontract CLI) = Solidity参照実装 (別リポジトリ)
│         本PJでは idris2-subcontract が同等の役割を担う
│
├── idris2-* Package Suite
│   │
│   ├── idris2-cdk (~/code/idris2-cdk)
│   │   └── [x] FRMonad.Core       # Failure-Recovery Monad
│   │
│   ├── idris2-yul (~/code/idris2-yul)
│   │   ├── [x] EVM.Primitives     # EVM FFI
│   │   ├── [x] EVM.Storage.*      # ERC-7201 slots
│   │   ├── [x] Compiler.EVM.*     # Yul codegen
│   │   └── [x] examples/ERC7546Proxy.idr  # UCS Proxy (693B runtime, 2025/01/10)
│   │           └── selector → Dictionary.getImplementation → DELEGATECALL
│   │
│   ├── idris2-subcontract (~/code/idris2-subcontract)
│   │   │   ※ Solidity版 mc (metacontract) の Idris2 相当
│   │   ├── [x] Subcontract.Standards.ERC7546.*  # UCS Proxy
│   │   ├── [x] Subcontract.Core.*               # Framework
│   │   ├── [x] Subcontract.Core.FR              # Failure-Recovery Monad (2025/01/10)
│   │   ├── [x] Subcontract.Std.Functions.ProxyFactory  # CREATE2 ERC-7546 deployment (2025/01/10)
│   │   │       ├── deployProxy(dictionary, salt) → proxy address
│   │   │       ├── buildInitCode → 771 bytes (78 init + 693 runtime)
│   │   │       └── computeProxyAddress → deterministic address
│   │   ├── [ ] Contract状態分析API  # lazy evm-lifecycle ask 向け
│   │   └── [ ] Upgrade検出API       # ERC7546 dictionary変更検出
│   │
│   ├── idris2-ouf (~/code/idris2-ouf)
│   │   │   ※ Optimistic Upgrader Framework
│   │   ├── [x] Main.Storages.Schema      # Storage slots
│   │   ├── [x] Main.Functions.Factory    # createUpgrader via ProxyFactory (2025/01/10)
│   │   │       └── CREATE2 deploys ERC-7546 proxy pointing to shared Dictionary
│   │   ├── [x] Main.Functions.ProposeUpgrade
│   │   ├── [x] Main.Functions.Vote
│   │   ├── [x] Main.Functions.Tally
│   │   └── [x] Main.Functions.AssignAuditor
│   │
│   ├── idris2-ouc (this repo)
│   │   ├── src/Main.idr          # FFI dispatch (9 commands)
│   │   │   ├── [x] CMD_INIT, GET_VERSION, GET_*_COUNT (Query)
│   │   │   ├── [x] CMD_GET_PROPOSAL (Query, Candid nat入力)
│   │   │   ├── [x] CMD_REGISTER/SUSPEND/REACTIVATE_AUDITOR (Update)
│   │   │   ├── [x] CMD_SUBMIT_PROPOSAL (Update, Candid text入力)
│   │   │   └── [x] testEthBlockNumber (HTTP Outcall, ic0_call_*)
│   │   ├── support/ic0/
│   │   │   ├── [x] canister_entry.c  # IC entry points
│   │   │   ├── [x] ic0_stubs.c       # FFI bridge
│   │   │   └── [x] wasi_stubs.c      # WASI compat
│   │   ├── src/OUC/
│   │   │   ├── [x] Core.idr       # 基本型定義
│   │   │   ├── [x] Lifecycle.idr  # 状態遷移
│   │   │   ├── [x] Obligations.idr
│   │   │   ├── [x] MultiSig.idr
│   │   │   ├── [x] Relay.idr
│   │   │   └── [x] Signatures.idr
│   │   │
│   │   ├── src/AuditorPool/
│   │   │   ├── [x] Core.idr       # 348行、FRMonad準拠
│   │   │   └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │   │
│   │   ├── src/Rewards/
│   │   │   ├── [x] Core.idr       # 260行、FRMonad準拠
│   │   │   └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │   │
│   │   ├── src/Proposals/
│   │   │   ├── [x] Core.idr
│   │   │   └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │   │
│   │   ├── src/HttpOutcall/
│   │   │   ├── [x] Core.idr
│   │   │   ├── [x] EvmRpc.idr
│   │   │   ├── [x] TxSender/
│   │   │   └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │   │
│   │   └── src/ERC7546/
│   │       ├── [x] Dictionary.idr
│   │       ├── [x] Upgrade.idr
│   │       └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │
│   ├── idris2-textdao (~/code/idris2-textdao)
│   │   └── [x] Reference impl     # UCSパターン適用例
│   │
│   ├── idris2-dfx-coverage (~/code/idris2-dfx-coverage)
│   │   ├── [x] ic-wasm instrument 連携
│   │   ├── [x] __get_profiling データ取得
│   │   └── [x] func_id → カバレッジ計算
│   │
│   └── idris2-wasm-coverage (未作成)    # 将来: Native WASM tracing
│       ├── [ ] WASM実行トレース収集
│       ├── [ ] PC → Idris2関数マッピング
│       └── [ ] Vibe Coding対応 (idris2-evm-coverage相当)
│
├── Failure-Aware Build Infrastructure (FABI)
│   │
│   ├── Reproducible Build Spec
│   │   ├── [ ] Build environment definition (Docker / Nix / Bazel)
│   │   ├── [ ] Source + lockfile + env hash schema
│   │   └── [ ] Build evidence format (hash chain)
│   │
│   ├── n-of-n Builder Network
│   │   ├── [ ] Independent builder roles
│   │   ├── [ ] Build result intersection protocol
│   │   └── [ ] Dispute / mismatch handling
│   │
│   ├── Build Rebinding Procedures
│   │   ├── [ ] Builder replacement flow
│   │   ├── [ ] Environment migration
│   │   └── [ ] Emergency rebuild path
│   │
│   └── Integration with OUC
│       ├── [ ] Build evidence → OUC proposal schema
│       ├── [ ] Auditor build verification tooling
│       ├── [ ] lazy build ask (Failure Sink診断)
│       └── [ ] mc build 証拠生成コマンド化
│
├── Self-Amending Protocol Layer
│   │
│   ├── Futarchy Annotation (PDF Section 9)
│   │   ├── [ ] 予測市場コントラクト
│   │   │   ├── [ ] AMM価格オラクル
│   │   │   └── [ ] 期待値シグナル取得API
│   │   ├── [ ] Annotation → Selection圧力変換
│   │   └── [ ] Observable outcome記録
│   │
│   ├── AI Agent Infrastructure
│   │   ├── [ ] Claude Skills定義
│   │   │   ├── [ ] オンチェーンデータ取得
│   │   │   ├── [ ] 予測市場価格読取り
│   │   │   └── [ ] Upgrade提案生成
│   │   ├── [ ] 定期監視ループ
│   │   │   ├── [ ] Annotation変化検出
│   │   │   └── [ ] Gap→Action変換
│   │   └── [ ] lazy evm-lifecycle統合
│   │
│   └── Governance-by-Observation
│       ├── [ ] 使用シグナル収集
│       ├── [ ] 失敗記録（FR semantics）
│       └── [ ] 自動淘汰メカニズム
│
├── External Dependencies
│   │
│   ├── Internet Computer (ICP)
│   │   ├── [x] Canister deployment
│   │   ├── [x] HTTP Outcall
│   │   └── [ ] Threshold ECDSA署名
│   │
│   └── EVM Chains
│       ├── [x] JSON-RPC接続
│       ├── [~] Transaction送信（TxSender）
│       └── [ ] マルチチェーン対応
│
└── Documentation & Specs
    ├── [x] Self-Amending Protocols.pdf
    ├── [x] FRC.pdf (FR Monad理論)
    ├── [x] AGA Loop.pdf
    ├── [x] SPEC.toml群の復活/再設計 (7ファイル復活済み)
    ├── [ ] Claude Skills仕様書
    ├── [x] FABI.md (Failure-Aware Build Infrastructure)
    └── [x] OUC-Spec.md (Optimistic Upgrader Canister)
```

## ERC-7546 Proxy Deployment Architecture (2025/01/10)

OUF (Optimistic Upgrader Framework) が ERC-7546 Proxy を CREATE2 でデプロイするアーキテクチャ。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  OUF Factory.createUpgrader()                                               │
│  ───────────────────────────────────────────────────────────────────────────│
│                                                                             │
│  1. upgraderId = getUpgraderCount()    ← salt for CREATE2                  │
│  2. dictAddr = getDictionary()         ← shared Dictionary                  │
│  3. proxyAddr = deployProxy(dictAddr, upgraderId)                          │
│  4. registerUpgrader(upgraderId, proxyAddr)                                 │
│  5. setUpgraderCount(upgraderId + 1)                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  ProxyFactory.deployProxy(dictionary, salt)                                 │
│  ───────────────────────────────────────────────────────────────────────────│
│                                                                             │
│  buildInitCode(dictionary):                                                 │
│    [00-32]  PUSH32 <dictionary>       ┐                                     │
│    [33-65]  PUSH32 DICTIONARY_SLOT    ├─ 66 bytes: store dict in slot      │
│    [66]     SSTORE                    ┘                                     │
│    [67-77]  PUSH2/DUP1/PUSH2/PUSH0/   ┐                                     │
│             CODECOPY/PUSH0/RETURN     ├─ 12 bytes: return runtime          │
│    [78+]    <runtime bytecode>        └─ 693 bytes: ERC7546Proxy           │
│                                                                             │
│  Total init code: 771 bytes                                                 │
│                                                                             │
│  CREATE2(value=0, offset=0, size=771, salt=upgraderId)                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Deployed ERC-7546 Proxy (693 bytes runtime)                                │
│  ───────────────────────────────────────────────────────────────────────────│
│                                                                             │
│  DICTIONARY_SLOT = 0x267691be3525af8a813d30db0c9e2bad...cff56f4            │
│                ↓                                                            │
│           sload(slot) → Dictionary address                                  │
│                                                                             │
│  Any external call:                                                         │
│    1. getSelector() → first 4 bytes of calldata                            │
│    2. STATICCALL dictionary.getImplementation(selector)                    │
│    3. DELEGATECALL to returned implementation                              │
│    4. Return/revert based on result                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Package Flow

```
idris2-yul                 idris2-subcontract              idris2-ouf
───────────────────        ───────────────────             ───────────────────
examples/                  Std/Functions/                  Functions/
  ERC7546Proxy.idr    →      ProxyFactory.idr         →     Factory.idr
    │                          │                              │
    │ compile                  │ embeds bytecode              │ imports
    ▼                          ▼                              ▼
  693B runtime         deployProxy(dict, salt)        createUpgrader()
                       computeProxyAddress()
```

### Deterministic Address Calculation

```
proxyAddress = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]

Where:
  - factory = OUF Factory contract address
  - salt = upgraderId (sequential counter)
  - initCode = 771 bytes (depends on dictionary address)
```

### GitHub References (idris2-ouc/pack.toml)

```toml
[custom.all.idris2-yul]
commit = "0ec96ff"  # ERC7546Proxy.idr added

[custom.all.idris2-subcontract]
commit = "794f5b5"  # ProxyFactory added
url = "https://github.com/shogochiai/idris2-subcontract"

[custom.all.idris2-ouf]
commit = "d4aaaaa"  # Factory → ProxyFactory integration
```

## Design Principle: Upgrade = Build Rebinding + Execution Rebinding

Self-Amending Protocolにおいて、Upgradeは単一の行為ではない。
2つのRebindingプロセスの合成である：

1. **Build Rebinding**: ビルド環境・再現性・運用主体の失敗からの回復
2. **Execution Rebinding**: コード意図・監査・活性の失敗からの回復

安全性は「正しさ」ではなく、**どちらの層もFailure Sinkにならないこと**で達成される。

```
Source Code → [FABI] → Bytecode + Evidence → [OUC] → Protocol State
              ↑ Build Rebinding              ↑ Execution Rebinding
```

## 凡例

- `[x]` 実装済み
- `[~]` 部分実装/テンプレートのみ
- `[ ]` 未実装

## Known Issues: RefC/WASM Bugs (2025/01/08)

| Bug | 症状 | 回避策 | 状態 |
|-----|------|--------|------|
| #1 | `==` 演算子が Int で壊れる | - | **解決済み** ([PR #3708](https://github.com/idris-lang/Idris2/pull/3708)) |
| #2 | IORef が WASM 呼び出し間で非永続化 | C static 変数で状態保持 | 回避中 |
| #3 | FFI 読み取りが 0 を返す | - | **解決済み** (設計理解不足、バグではなかった) |
| #4 | ic-wasm profiling データが上書きされる | インクリメンタルキャプチャ | **解決済み** (2025/01/09) |

### Bug #3 解決報告 (2025/01/08)

**結論**: Bug #3 はバグではなく、**RefC 埋め込みパターンの理解不足**だった。

**経緯**:
1. `tests/ic0-ffi-repro/` で最小再現テスト作成時、`ic0_time()` が 0 を返す問題が発生
2. 長時間の調査の結果、WASM `call_indirect` の型不一致を疑った
3. しかし **本体の `support/ic0/canister_entry.c` は正しく実装されていた**
4. テスト再現用のスタブ (`ic0_test_stubs.c`) だけが誤っていた

**根本原因**:
```c
// ❌ 誤り: closure を捨てている (IO が実行されない)
(void)__mainExpression_0();

// ✅ 正解: trampoline で IO を実行する
Value closure = __mainExpression_0();
idris2_trampoline(closure);
```

**RefC の仕様**:
- `__mainExpression_0()` は IO action を表す **closure を返す**（実行はしない）
- 実行するには `idris2_trampoline()` を呼ぶ必要がある
- これは Idris2 RefC backend の正しい設計であり、バグではない

**教訓**:
1. テスト再現コードを書く際は、本体の実装パターンを踏襲すること
2. RefC 埋め込みでは `idris2_trampoline(__mainExpression_0())` が必須
3. CLAUDE.md に RefC 統合の基礎を追記済み

### Research Questions (RefC FFI Bug 調査)

```
RQ1: 生成Cコードは正しいか？ ✅ 調査完了
├── RQ1.1: ouc_get_arg_i32 の呼び出しは正しく生成されているか？ → 正しい
├── RQ1.2: PrimIO の展開は正しいか？ → 正しい
└── RQ1.3: Int64 vs Int32 の型不一致はないか？ → 型は一致

RQ2: Emscripten変換は正しいか？ ✅ 調査完了 (2025/01/08)
├── RQ2.1: WASM関数シグネチャは一致しているか？ → 一致
├── RQ2.2: メモリレイアウトは正しいか？ → 正しい (offset=8 for i64 field)
└── RQ2.3: 呼び出し規約は維持されているか？ → 維持されている

RQ3: IC0実行時の問題か？ ✅ 調査完了 (2025/01/08)
├── RQ3.1: グローバル変数は初期化されているか？ → idris2_predefined_Int64 は正常
├── RQ3.2: メモリアクセスは正しいアドレスを指しているか？ → 正しい
└── RQ3.3: スタック/ヒープ破壊はないか？ → 未確認だが可能性低

RQ4: RefCバックエンド固有の問題か？ ✅ 調査完了 (2025/01/08)
├── RQ4.1: 他のバックエンド (JS等) で同じ問題が起きるか？ → 未確認
├── RQ4.2: Idris2コミュニティで既知の問題か？ → 未報告
└── RQ4.3: 最小再現ケースを作成できるか？ → **再現成功** (tests/ic0-ffi-repro)、根本原因特定

RQ5: Idris2 FFI 返り値処理の問題か？ → 棄却 (2025/01/08)
├── RQ5.1: idris2_mkInt64 の返り値が正しく boxed されているか？ → 正常 (テスト通過)
├── RQ5.2: idris2_trampoline でクロージャ結果が取得されているか？ → 正常
└── RQ5.3: IOモナド展開時に結果が失われていないか？ → 正常

RQ6: IC0 System API 固有の問題か？ ✅ 確認 (2025/01/08)
├── RQ6.1: IC0 import (WASM外部関数) と通常FFI (リンク済みC) の違いは？ → 違いあり、IC0で問題発生
├── RQ6.2: Emscripten WASM と ICP WASM の呼び出し規約は互換か？ → 要調査 (原因の可能性)
└── RQ6.3: dfx環境での最小再現ケースで問題が起きるか？ → **再現成功** (tests/ic0-ffi-repro)
```

### 調査結果 (2025/01/08)

**RefC Value表現の理解**:
```c
// Unboxed判定: ポインタ下位2ビットをチェック
#define idris2_vp_is_unboxed(p) ((uintptr_t)(p)&3)

// Int64抽出: Value_Int64構造体の.i64フィールドを直接参照
#define idris2_vp_to_Int64(p) (((Value_Int64 *)(p))->i64)

// 0-99は事前確保された配列を使用
Value *idris2_mkInt64(int64_t i) {
  if (i >= 0 && i < 100)
    return (Value *)&idris2_predefined_Int64[i];
  // ... allocate new Value_Int64
}
```

### 解決済み: Bug #1 - 比較演算子 (2025/01/08)

**根本原因**: `idris2_extractInt` 関数 (`runtime.c`) が unboxed values に対して `idris2_vp_to_Int32` マクロを使用していた。このマクロは 32bit プラットフォーム (WASM32) で `UINTPTR_WIDTH` が未定義の場合、unboxed ポインタを `Value_Int32*` として不正にデリファレンスしていた。

**修正内容**:
```c
// runtime.c:160-166
int idris2_extractInt(Value *v) {
  if (idris2_vp_is_unboxed(v))
    // FIX: Always extract via shift for unboxed values
    return (int)((uintptr_t)(v) >> idris2_vp_int_shift);
  // ... boxed handling unchanged
}
```

**PR**: [idris-lang/Idris2#3708](https://github.com/idris-lang/Idris2/pull/3708)
- テスト追加: `tests/refc/wasm32cmp001`
- 全 RefC テスト (21/21) パス確認済み

### Bug #4 解決報告 (2025/01/09)

**症状**: `lazy dfx ask --steps=4` で "Functions covered: 1" と表示 (期待値 ~66)

**調査経緯**:
1. `registerAuditor` 後: 9873 bytes のプロファイリングデータ ✓
2. `submitProposal` 後: 384 bytes に縮小 ✗ → データが上書きされている

**根本原因**:
- ic-wasm は profiling buffer を stable memory page 0 に配置
- OUC canister も UPDATE 時に stable memory page 0 に書き込み
- 結果: profiling buffer が canister のデータで上書きされる

**試行1 (失敗)**: `--start-page 1000`
```bash
ic-wasm ... instrument --start-page 1000
```
→ canister が stable memory を page 1000 まで事前確保していないため WASM trap

**解決策**: インクリメンタルプロファイリング
- 各 UPDATE 後に即座にプロファイリングデータをキャプチャ
- 蓄積ファイルに追記 (`/tmp/dfx_profiling_accum_*.txt`)
- 全キャプチャから unique func_id をカウント

**実装**:
- `captureProfilingData`: UPDATE 後に `__get_profiling` を呼び出し蓄積
- `countAccumulatedFuncs`: 全データから unique positive func_ids をカウント
- `runTestScenarios`: 3-tuple `(success, total, funcsCovered)` を返す

**結果**:
- Before: `Functions covered: 1`
- After: `Functions covered: 66`
- 13/13 シナリオ pass、14043K cycles 実行

**教訓**: stable memory を共有するコンポーネント間の競合は、タイミングベースの回避策（即時読み取り＆蓄積）で解決可能。

### 残課題: Bug #2

**調査結果 (2025/01/08 追加)**:

WASM分析で以下を確認:
- `idris2_predefined_Int64` 配列: 正常に初期化 (データセグメント @ 0x0C80)
- `Value_Int64` 構造体: 正しいレイアウト (header:4B + padding:4B + i64:8B = 16B)
- FFI引数読み取り: `i64.load offset=8` で正しいオフセット使用
- C側FFI関数: 正常動作 (回避策が機能している証拠)

**現在の有力仮説**:
1. ~~idris2_predefined_Int64配列の初期化問題~~ → 棄却 (正常に初期化されている)
2. ~~Value_Int64のアライメント問題~~ → 棄却 (オフセット計算は正しい)
3. **Idris2 FFI 返り値処理**: IOモナド展開・trampoline実行時に結果が失われている可能性

**最小再現テスト結果 (2025/01/08)**:

`tests/ffi-repro/` で Native/WASM 両方でテスト実施:
```
Test1 return42: 42     ✅ (期待値: 42)
Test2 addOne(10): 11   ✅ (期待値: 11)
Test3 getResult: 100   ✅ (期待値: 100)
Test4 roundtrip(20): 30 ✅ (期待値: 30)
Total failures: 0
```

**結論**: 単純な FFI (int64_t 返り値) は Native/WASM 両方で正常動作。
Bug #3 は単純 FFI では再現しない。

**ICP 環境テスト結果 (2025/01/08)**:

`tests/ic0-ffi-repro/` で ICP 環境 (dfx local) でテスト実施:
```
dfx canister call ic0_test test_ffi '()'
→ (0 : nat)
```

**Bug #3 再現成功!** `ic0_time()` の返り値が 0 になっている。

**根本原因の仮説**:
1. 単純 FFI (リンク済み C 関数) → 正常動作 (tests/ffi-repro)
2. IC0 import (WASM 外部関数) → **Bug #3 発生** (tests/ic0-ffi-repro)

**確定した原因 (2025/01/08)**:

追加テストで問題を切り分け:
```
test_ffi (Idris2 FFI経由):    0  ← Bug #3
test_direct (C直接呼び出し):  1,767,860,499,857,963,000  ← 正常
```

**結論**: IC0 import 自体は正常動作。**Idris2 FFI レイヤー**が返り値を失っている。

**決定的な発見 (2025/01/08)**:

デバッグログで確認:
```
test_c_wrapper (C直接):  val=1767860769769478000  ← ログ出力あり
test_ffi (Idris2 FFI):   (ログ出力なし)           ← C関数が呼ばれていない!
```

**根本原因**: Idris2 closure が作成されるが、trampoline による実行時に
**FFI C 関数に到達していない**。Closure 実行自体が失敗している。

**詳細分析**:
1. `getTimeIdris` は closure を作成 (`idris2_mkClosure`)
2. `idris2_trampoline` が closure を実行
3. しかし closure 内の `IC0Test_prim__ic0Time` が呼ばれない
4. 結果として 0 が返される

**根本原因特定 (2025/01/08)**:

`idris2_trampoline` の `call_indirect` で **型不一致** が発生している。

**WASMコード分析**:
```wat
;; idris2_trampoline (func 26) の分岐テーブル
;; arity=1 の場合、case 1 に分岐
call_indirect (type 1)   ;; type 1 = () -> i32 (引数なし!)

;; しかし IC0Test_prim__ic0Time は
(func (;22;) (type 0) ...)   ;; type 0 = (i32) -> i32 (1引数)
```

**型の定義**:
- type 0 = `(param i32) (result i32)` — 1引数
- type 1 = `(result i32)` — 引数なし

**ロジックエラー**:
| arity | trampoline選択 | 期待値 |
|-------|----------------|--------|
| 0 | type 0 (i32→i32) | type 1 (→i32) |
| 1 | type 1 (→i32) | type 0 (i32→i32) |

**型が1つずれている！** Idris2 RefC runtime の `idris2_trampoline.c` で
arity に基づく関数型選択のマッピングが誤っている可能性。

**WASM の挙動**:
`call_indirect` で型が一致しない場合、WASM 仕様では **trap** が発生する。
ICP の WASM ランタイムはこの trap を捕捉し、結果として 0 を返している。

**次ステップ**:
1. ✅ 根本原因特定完了
2. Idris2 RefC ランタイム (`idris2_trampoline.c`) のソースを確認
3. Idris2 本体に Issue を提出 (WASM分析付き)
4. ワークアラウンド: FFI関数を直接呼び出す方式を検討

**参考**: https://github.com/shogochiai/idris2-evm-coverage (EVM版トレースツール)

## Candid I/O 実装進捗 (2025/01/08)

### Phase 1-2: 完了 ✅

| 機能 | 状態 | 実装場所 |
|------|------|----------|
| Candid nat 引数パース (LEB128) | ✅ | `canister_entry.c:104-141` |
| Candid text 引数パース | ✅ | `canister_entry.c:151-198` |
| `getProposal(nat)` | ✅ | Query, proposal ID で検索 |
| `submitProposal(text)` | ✅ | Update, proposal 作成 |

### Phase 3: 完了 ✅ (2025/01/08)

**解決した制約: ICP 状態永続化**

| ストレージ | コール内 | コール間 | 実装 |
|-----------|---------|---------|------|
| Idris2 IORef | ✅ | ❌ | 使用せず |
| C グローバル変数 | ✅ | ✅ | `ouc_proposal_count`, `ouc_auditor_count` |

**実装内容**:
- `ic0_stubs.c`: `ouc_proposal_count`, `ouc_get_proposal_count()`, `ouc_inc_proposal_count()`
- `canister_entry.c`: Query/Update メソッドを C-backed storage 直接参照に変更

**E2E テスト結果**:
```
submitProposal → {"id":0}  ✅
getProposalCount → 1       ✅ (永続化!)
getProposal(0) → found     ✅ (永続化!)
registerAuditor → cnt=1    ✅
getAuditorCount → 1        ✅ (永続化!)
```

### Phase 4+: idris2-cdk Candidable 自動派生

`idris2-cdk` の既存インフラを活用した長期計画:

```
idris2-cdk/ICP/Candid/Types.idr
├── Candidable 型クラス (encode/decode 抽象化)
├── CandidType (型記述子)
├── hashFieldName (フィールドハッシュ)
└── 基本型インスタンス (Nat, Bool, String, List, Maybe, ...)
```

**ロードマップ**:

1. **レイヤA: `derive Candidable`**
   - TTImp で record/data → インスタンス生成
   - 既存手書き例 (`EcdsaKeyId`, `EcdsaCurve`) をテンプレートに
   - FRMonad と統合 (decode 失敗を構造化)

2. **レイヤB: `.did` 自動生成**
   - 公開 API 集合 → service 型
   - `query`/`update` アノテーション規約
   - `CandidResult e a` でエラー表現統一

3. **レイヤC: 境界安全性**
   - `fromCandid : CandidValue -> Maybe a` を `FR` に持ち上げ
   - `DecodeError` 分類との統合

**設計原則**:
- C 手書きパーサ (Phase 1-2) → Idris2 自動派生 (Phase 4+) へ段階移行
- 型安全性を徐々に向上させつつ、MVP は迅速にデリバリー

## HTTP Outcall 実装進捗 (2025/01/08)

### Phase 1: IC アーキテクチャ調査 ✅

HTTP Outcall は IC 管理キャニスター (`aaaaa-aa`) への Inter-canister call として実装される:
1. `ic0_call_new` - コール構造を初期化 (callee, method, callbacks)
2. `ic0_call_data_append` - Candid エンコードされた引数を追加
3. `ic0_call_cycles_add128` - HTTP リクエストのサイクルコストを支払い
4. `ic0_call_perform` - 非同期コールを実行

### Phase 2: C側実装 ✅

**実装ファイル**: `support/ic0/canister_entry.c`

| 機能 | 状態 | 行番号 |
|------|------|--------|
| LEB128 エンコード (符号なし/符号付き) | ✅ | 604-633 |
| Candid text/blob エンコード | ✅ | 635-648 |
| HttpRequestArgs Candid 構築 | ✅ | 668-793 |
| `testEthBlockNumber` メソッド | ✅ | 795-855 |
| Reply/Reject コールバック | ✅ | 560-598 |

**HttpRequestArgs 構造** (Candid):
```candid
record {
  url : text;                    // "https://eth.llamarpc.com"
  max_response_bytes : opt nat64; // 2048
  method : variant { post };
  headers : vec record { name: text; value: text };
  body : opt blob;               // JSON-RPC body
  transform : opt ...;           // None
}
```

### Phase 3: E2E テスト結果 ✅

```
dfx canister call ouc testEthBlockNumber
→ {"status":"call_initiated","candid_len":209}  ✅
```

- `candid_len: 209` - HttpRequestArgs の Candid エンコード成功
- `call_initiated` - `ic0_call_perform()` が 0 (成功) を返却

**制限事項**:
- ローカル replica では HTTP Outcall に追加設定が必要
- コールバック関数の WASM テーブルインデックス設定が必要
- 本番 (mainnet) での完全 E2E テストは今後実施

### 今後の展開

| タスク | 優先度 | 状態 |
|--------|--------|------|
| Candid レスポンスデコード | P1 | 設計済み |
| エラーハンドリング強化 | P2 | 未着手 |
| 複数 RPC エンドポイント対応 | P2 | 未着手 |
| Mainnet E2E テスト | P1 | 未着手 |

## Spec-Test Parity (LLM自動検証)

### 課題解決ツリー

```
課題: Spec-Test Parity Gap を自動検出したい
│
├── 解決策: SPEC.toml (正規フォーマット) + テスト関数
│   │
│   ├── SPEC.toml (lazy 正規フォーマット)
│   │   ├── [[spec]] id = "REQ_XXX_NNN" description = "..."
│   │   ├── [[type]] id = "REQ_TYPE_XXX_NNN" text = "..."
│   │   ├── [[spec_area]] + [[spec_area.sub_feature]] (組織化)
│   │   └── [definitions] で変数置換 (${module_self} 等)
│   │
│   └── Tests/AllTests.idr (正規フォーマット)
│       │
│       │   allTests : List TestDef
│       │   allTests = [
│       │     test "REQ_AUD_CMF_001" "description" test_function,
│       │     test "REQ_TYPE_AUD_001" "runAudit function" test_runAudit,
│       │     ...
│       │   ]
│       │
│       └── test 第1引数 = SPEC id でマッピング
│
├── Parity 検証 (LLM実行可能)
│   │
│   │   SPEC.toml                    allTests リスト
│   │   ─────────────────────        ─────────────────────────────────
│   │   [[spec]] id="REQ_AUD_001"    test "REQ_AUD_001" "desc" fn
│   │   [[type]] id="REQ_TYPE_001"   test "REQ_TYPE_001" "desc" fn
│   │
│   ├── ✅ Parity: SPEC id に対応する test エントリ存在
│   └── ❌ Gap: SPEC id はあるが allTests に未登録 (LLMが指摘)
│
└── 適用先
    │
    ├── lazy CLI (~/code/lazy) [正規フォーマット]
    │   │   → `lazy core ask --steps=1,2`
    │   │
    │   │   SPEC format: [[spec]] id="REQ_XXX_NNN"
    │   │                [[type]] id="REQ_TYPE_XXX_NNN"
    │   │                [[spec_area]] + [[spec_area.sub_feature]]
    │   │
    │   └── [x] src/Audit/SPEC.toml 等 (100+ specs)
    │
    ├── LazyDfx (~/code/lazy/pkgs/LazyDfx) [idris2-chez]
    │   │   → `lazy core ask --steps=1,2`
    │   │
    │   │   SPEC format: [REQ_*] (簡易版、正規化が必要)
    │   │
    │   ├── [x] DfxTypes/SPEC.toml + Tests/AllTests.idr
    │   ├── [x] DfxCandid/SPEC.toml + Tests/AllTests.idr
    │   └── [~] DfxCanister/SPEC.toml (テストはIO依存)
    │
    └── idris2-ouc (src/*) [idris2-wasm for ICP]
        │   → `lazy dfx ask --steps=1,2` (未実装)
        │
        │   SPEC format: [[spec]] id="${prefix}_XXX_NNN" (旧形式)
        │   → 正規フォーマット移行が必要
        │
        ├── [~] OUC/SPEC.toml + Tests/CoreTests.idr
        ├── [~] Integration/SPEC.toml + Tests/AllTests.idr
        ├── [ ] AuditorPool/SPEC.toml (テスト未作成)
        ├── [ ] Rewards/SPEC.toml (テスト未作成)
        ├── [ ] Proposals/SPEC.toml (テスト未作成)
        ├── [ ] HttpOutcall/SPEC.toml (テスト未作成)
        └── [ ] ERC7546/SPEC.toml (テスト未作成)
```

### SPEC.toml フォーマット比較

| プロジェクト | フォーマット | 例 | 状態 |
|-------------|-------------|-----|------|
| **lazy CLI** (正規) | `[[spec]] id="REQ_XXX_NNN"` | `REQ_AUD_CMF_001` | ✅ 標準 |
| LazyDfx | `[REQ_*]` セクション | `[REQ_NETWORK_TYPES]` | 簡易版 |
| idris2-ouc | `[[spec]] id="${prefix}_XXX"` | `POOL_REG_001` | 旧形式 |

**正規フォーマット要素**:
- `[[spec]]` + `[[type]]`: 仕様とSI Parity型定義
- `[[spec_area]]` + `[[spec_area.sub_feature]]`: 階層的組織化
- `[definitions]`: 変数置換 (`${module_self}`, `${fn_runAudit}` 等)
- `priority`, `tags`: メタデータ

### LLMによるParity Gap検出例

```
# lazy CLI (正規フォーマット)
$ lazy core ask src/Ask --steps=1,2

Step1: SPEC.toml の [[spec]]/[[type]] id 抽出
  → [REQ_AUD_CMF_001, REQ_AUD_PSF_001, REQ_TYPE_AUD_001, ...]

Step2: Tests/AllTests.idr の allTests リストから test 第1引数抽出
  → test "REQ_AUD_CMF_001" "..." ...
  → test "REQ_TYPE_AUD_001" "..." ...

Step3: SPEC id ↔ test id マッチング
  → ✅ REQ_AUD_CMF_001: test エントリあり
  → ❌ REQ_AUD_NEW_001: test エントリなし (Gap)

結果: Parity 98/100 (2 Gaps detected)
```

```
# idris2-wasm (ICP) プロジェクト ※lazy dfx ask 未実装
$ lazy dfx ask src/AuditorPool --steps=1,2

Step1: SPEC.toml の [[spec]] id 抽出
  → [POOL_REG_001, POOL_REG_002, POOL_SEL_001, ...]

Step2: Tests/AllTests.idr 検索
  → (テストファイル未作成)

結果: Gap ❌ (16件のSPECに対しテスト0件)
```

### 設計原則

1. **正規フォーマット準拠**:
   - SPEC: `[[spec]] id="REQ_XXX_NNN"` + `[[type]] id="REQ_TYPE_XXX_NNN"`
   - Test: `test "REQ_XXX_NNN" "description" test_fn` in `allTests : List TestDef`
2. **LLM代替可能**: 人間もLLMも同じルールでParity Gap検証可能
3. **段階的適用**: 全REQにテスト必須ではなく、Gap縮小を可視化
4. **TDVC互換**: Test-Driven Vibe Coding のフィードバックループに統合

### 注意: Coverage との違い

| 概念 | 対象 | 検出内容 |
|------|------|----------|
| **Spec-Test Parity** | SPEC.toml ↔ テスト関数 | 仕様に対応するテストの有無 |
| **Test Coverage** (Step4) | テスト実行 → コードパス | 実行時にどのコードが通ったか |

Spec-Test Parity Gap = 「仕様書いたけどテスト書いてない」
Test Coverage Gap = 「テスト書いたけど実行されてないコードがある」

## idris2-dfx-coverage 課題解決ツリー

### 概要

```
目標: lazy dfx ask --steps=4 で Test Coverage Gap を検出
│
├── 依存関係
│   ├── idris2-coverage (元祖/参照実装)
│   ├── idris2-evm-coverage (EVM版、アーキテクチャ参考)
│   └── idris2-dfx-coverage (NEW: WASM/ICP版)
│
└── 統合先
    └── lazy dfx ask --steps=4 → idris2-dfx-coverage 呼び出し
```

### Phase 1: WASM 実行トレース取得

```
課題: ICP replica 上での WASM 実行トレースを取得する
│
├── 方式A: ICP replica instrumentation
│   │
│   ├── 調査項目
│   │   ├── [ ] dfx replica のトレース機能有無
│   │   ├── [ ] IC sandbox のデバッグオプション
│   │   └── [ ] canister_inspect_message 活用可能性
│   │
│   ├── 利点: 実環境に近いトレース
│   └── 欠点: ICP 側の対応依存、変更困難
│
├── 方式B: カスタム WASM ランタイム (推奨)
│   │
│   ├── 実装項目
│   │   ├── [ ] wasmtime/wasmer に instrumentation 追加
│   │   ├── [ ] 関数呼び出しフック (call/call_indirect)
│   │   ├── [ ] 基本ブロックトレース (br/br_if/br_table)
│   │   └── [ ] ic0_* スタブ実装 (IC System API mock)
│   │
│   ├── 利点: 完全制御可能、オフライン実行
│   └── 欠点: IC System API の正確な模倣が必要
│
├── 方式C: WASM バイナリ rewrite
│   │
│   ├── 実装項目
│   │   ├── [ ] wasm-tools/walrus で instrumentation 注入
│   │   ├── [ ] 各関数入口に counter 挿入
│   │   ├── [ ] coverage 結果を stable memory に書き込み
│   │   └── [ ] テスト後に coverage データ読み出し
│   │
│   ├── 利点: 実 ICP replica で動作可能
│   └── 欠点: WASM サイズ増大、パフォーマンス影響
│
└── 決定: 方式B (カスタムランタイム) を推奨
    └── 理由: EVM版と同アーキテクチャ、制御可能
```

### Phase 2: PC → Idris2 関数マッピング

```
課題: WASM program counter を Idris2 ソース位置に逆マップ
│
├── Step 2.1: ソースマップ生成
│   │
│   ├── 調査項目
│   │   ├── [ ] emcc -g オプションで DWARF 情報生成
│   │   ├── [ ] wasm-sourcemap 形式の利用可能性
│   │   └── [ ] Idris2 RefC → C のソース位置保持
│   │
│   ├── 課題
│   │   ├── Idris2 → C → WASM の2段階変換
│   │   ├── 中間 C コードとの対応が必要
│   │   └── インライン化による位置喪失
│   │
│   └── 出力: WASM func_idx → C line → Idris2 func
│
├── Step 2.2: 関数名抽出
│   │
│   ├── 実装項目
│   │   ├── [ ] WASM name section パース
│   │   ├── [ ] Idris2 mangling 規則の逆変換
│   │   │   └── 例: Main_main → Main.main
│   │   └── [ ] RefC runtime 関数の除外フィルタ
│   │
│   └── 出力: 実行された Idris2 関数名リスト
│
└── Step 2.3: カバレッジマップ構築
    │
    ├── 実装項目
    │   ├── [ ] 関数レベルカバレッジ (hit/miss)
    │   ├── [ ] 基本ブロックカバレッジ (オプション)
    │   └── [ ] テストケース → カバー関数の関連付け
    │
    └── 出力: CoverageReport JSON
```

### Phase 3: IC System API モック

```
課題: テスト実行時に ic0_* 関数を模倣する
│
├── 必須 API (idris2-ouc で使用中)
│   │
│   ├── 状態管理
│   │   ├── [ ] ic0_stable_size, ic0_stable_grow
│   │   ├── [ ] ic0_stable_read, ic0_stable_write
│   │   └── [ ] ic0_stable64_* (64bit版)
│   │
│   ├── メッセージ I/O
│   │   ├── [ ] ic0_msg_arg_data_size, ic0_msg_arg_data_copy
│   │   ├── [ ] ic0_msg_reply, ic0_msg_reply_data_append
│   │   └── [ ] ic0_msg_reject
│   │
│   ├── 呼び出し元情報
│   │   ├── [ ] ic0_msg_caller_size, ic0_msg_caller_copy
│   │   └── [ ] ic0_canister_self_size, ic0_canister_self_copy
│   │
│   ├── 時間・乱数
│   │   ├── [ ] ic0_time
│   │   └── [ ] ic0_performance_counter
│   │
│   └── Inter-canister call (HTTP Outcall)
│       ├── [ ] ic0_call_new, ic0_call_data_append
│       ├── [ ] ic0_call_cycles_add128
│       └── [ ] ic0_call_perform
│
├── モック実装方針
│   │
│   ├── テスト入力
│   │   └── JSON/TOML でテストシナリオ定義
│   │       └── { caller: "xxx", args: "DIDL...", time: 1234 }
│   │
│   ├── 状態管理
│   │   └── インメモリ stable memory エミュレーション
│   │
│   └── 非決定性
│       └── ic0_time, performance_counter は固定値 or シード
│
└── 参考: support/ic0/ic0_stubs.c の実装を流用
```

### Phase 4: lazy dfx ask 統合

```
課題: lazy dfx ask --steps=4 から idris2-dfx-coverage を呼び出す
│
├── CLI インターフェース
│   │
│   ├── 入力
│   │   ├── --target <dir>: Idris2 プロジェクトルート
│   │   ├── --wasm <path>: ビルド済み WASM ファイル
│   │   ├── --tests <path>: テスト定義 (JSON/TOML)
│   │   └── --sourcemap <path>: ソースマップ (optional)
│   │
│   └── 出力
│       ├── coverage.json: カバレッジ結果
│       ├── uncovered.txt: 未カバー関数リスト
│       └── exit code: 0=成功, 1=閾値未達
│
├── lazy dfx ask 側の実装
│   │
│   ├── [ ] Step4 の追加 (StepCodeCoverage)
│   ├── [ ] idris2-dfx-coverage バイナリ呼び出し
│   ├── [ ] 結果パース・AuditReport 統合
│   └── [ ] T-I Parity スコア計算への組み込み
│
└── 出力フォーマット (idris2-coverage 互換)
    │
    └── {
          "total_functions": 42,
          "covered_functions": 38,
          "coverage_percent": 90.5,
          "uncovered": ["Foo.bar", "Baz.qux", ...],
          "by_module": { "Main": 95.0, "OUC.Core": 88.0, ... }
        }
```

### Phase 5: ビルドパイプライン統合

```
課題: 既存ビルドフローにカバレッジ計測を組み込む
│
├── ビルドステップ
│   │
│   ├── 1. pack build ouc.ipkg
│   │   └── 通常ビルド (RefC → C)
│   │
│   ├── 2. emcc with debug info
│   │   └── emcc -g -gsource-map ... → ouc.wasm + ouc.wasm.map
│   │
│   ├── 3. テスト実行 (idris2-dfx-coverage)
│   │   └── idris2-dfx-coverage run --wasm ouc.wasm --tests tests.json
│   │
│   └── 4. レポート生成
│       └── coverage.json, coverage.html (optional)
│
├── Makefile/pack 統合
│   │
│   ├── [ ] make coverage ターゲット追加
│   ├── [ ] pack.toml へのフック登録
│   └── [ ] CI 統合 (GitHub Actions)
│
└── テスト定義フォーマット
    │
    └── tests.json
        [
          { "name": "getVersion",
            "method": "getVersion",
            "args": "",
            "expect": { "type": "text", "pattern": "1\\.0" } },
          { "name": "registerAuditor",
            "method": "registerAuditor",
            "args": "DIDL...",
            "expect": { "type": "contains", "value": "cnt=" } }
        ]
```

### 実装優先度

| Phase | タスク | 難易度 | 依存 | 優先度 |
|-------|--------|--------|------|--------|
| 1B | カスタム WASM ランタイム | 高 | wasmtime | P0 |
| 2.2 | 関数名抽出 (name section) | 中 | - | P0 |
| 3 | ic0_* 基本モック | 中 | Phase 1 | P0 |
| 2.1 | ソースマップ生成 | 高 | emcc 調査 | P1 |
| 2.3 | カバレッジマップ構築 | 中 | Phase 2.2 | P1 |
| 4 | lazy dfx ask 統合 | 中 | Phase 1-3 | P1 |
| 5 | ビルドパイプライン | 低 | Phase 4 | P2 |

### 参考リソース

- `idris2-coverage`: ~/code/idris2-coverage (元祖)
- `idris2-evm-coverage`: ~/code/idris2-evm-coverage (EVM版)
- `wasmtime`: https://github.com/bytecodealliance/wasmtime
- `wasm-tools`: https://github.com/bytecodealliance/wasm-tools
- IC System API: https://internetcomputer.org/docs/references/ic-interface-spec

## 優先度別タスク

### P0: 基盤整備（今すぐ必要）
0. ✅ **RefC FFI Bug #1 解決 (2025/01/08)** - [PR #3708](https://github.com/idris-lang/Idris2/pull/3708)
   - `==`, `<`, `>`, `<=`, `>=` 演算子が WASM32 で正常動作
   - Bug #2, #3 は引き続き回避策使用中
1. ✅ 削除されたSPEC.tomlの復活 (2025/01/07完了)
2. `lazy evm ask` のstub解除
3. `lazy dfx ask` のstub解除

### P1: lifecycle統合
1. [~] `lazy evm-lifecycle ask` 実装 (進行中 2025/01/10)
   - ✅ LazyEvmLifecycle パッケージビルド成功
   - ✅ cast出力パース (storage slot, block number)
   - ✅ Dictionary getImplementation クエリ
   - ✅ queryAllImplementations バッチクエリ
   - ✅ queryDictionaryOwner クエリ
   - ✅ hasCode (zombie reference検出)
   - [ ] Local vs Deployed impl比較
   - [ ] E2Eテスト (Anvil + cast)
2. ✅ `lazy dfx-lifecycle ask` 実装 (2025/01/10完了)
   - Canister upgrade検出 (local vs deployed hash)
   - Stable memory migration hooks検出
   - Controller権限分析
   - Cycles残高警告
3. idris2-subcontract Upgrade検出API
   - ERC7546 dictionary変更検出
   - Contract状態分析
4. Auditor自動割当て

### P2: Self-Amending基盤
1. Futarchy予測市場コントラクト
2. Claude Skillsオンチェーンアクセス
3. AI Agent監視ループ

### P3: 本番運用
1. マルチチェーン対応
2. Threshold ECDSA
3. 自動淘汰メカニズム
