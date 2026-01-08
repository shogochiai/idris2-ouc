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
│   │   └── [ ] lazy evm-lifecycle ask # デプロイ/Upgrade助言
│   │       ├── [ ] Upgrade proposal検出
│   │       ├── [ ] mc CLI連携
│   │       └── [ ] Auditor割当て推奨
│   │
│   └── ICP側
│       ├── [ ] lazy dfx ask           # Canister分析（stub）
│       │   ├── [ ] Candid interface検証
│       │   ├── [ ] Cycle消費分析
│       │   └── [ ] HTTP Outcall依存検出
│       └── [ ] lazy dfx-lifecycle ask # Canister lifecycle助言
│           ├── [ ] dfx deploy連携
│           ├── [ ] Canister upgrade検出
│           ├── [ ] Stable memory migration
│           └── [ ] Controller権限管理
│
├── idris2-* Package Suite
│   │
│   ├── idris2-cdk (~/code/idris2-cdk)
│   │   └── [x] FRMonad.Core       # Failure-Recovery Monad
│   │
│   ├── idris2-yul (~/code/idris2-yul)
│   │   ├── [x] EVM.Primitives     # EVM FFI
│   │   ├── [x] EVM.Storage.*      # ERC-7201 slots
│   │   └── [x] Compiler.EVM.*     # Yul codegen
│   │
│   ├── idris2-subcontract (~/code/idris2-subcontract)
│   │   ├── [x] Subcontract.Standards.ERC7546.*  # UCS Proxy
│   │   ├── [x] Subcontract.Core.*               # Framework
│   │   └── cli/mc                               # MetaContract CLI
│   │       ├── [x] mc init
│   │       ├── [x] mc build
│   │       ├── [~] mc deploy      # テンプレートのみ
│   │       └── [~] mc upgrade     # テンプレートのみ
│   │
│   ├── idris2-ouc (this repo)
│   │   ├── src/Main.idr          # FFI dispatch (7 commands)
│   │   │   ├── [x] CMD_INIT, GET_VERSION, GET_*_COUNT (Query)
│   │   │   └── [x] CMD_REGISTER/SUSPEND/REACTIVATE_AUDITOR (Update)
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
│   └── idris2-wasm-coverage (未作成)    # ← NEW
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
| #3 | FFI 読み取りが 0 を返す | C 直接呼び出し (※Idris2バイパス) | 回避中 |

**※ Bug #3の回避策はIdris2の型安全性・Vibe Codingを無効化するため、根本解決が必須。**

### Research Questions (RefC FFI Bug 調査)

```
RQ1: 生成Cコードは正しいか？ ✅ 調査完了
├── RQ1.1: ouc_get_arg_i32 の呼び出しは正しく生成されているか？ → 正しい
├── RQ1.2: PrimIO の展開は正しいか？ → 正しい
└── RQ1.3: Int64 vs Int32 の型不一致はないか？ → 型は一致

RQ2: Emscripten変換は正しいか？ 🔍 要調査
├── RQ2.1: WASM関数シグネチャは一致しているか？
├── RQ2.2: メモリレイアウトは正しいか？ ← 有力仮説
└── RQ2.3: 呼び出し規約は維持されているか？

RQ3: IC0実行時の問題か？ 🔍 要調査
├── RQ3.1: グローバル変数は初期化されているか？ ← 有力仮説
├── RQ3.2: メモリアクセスは正しいアドレスを指しているか？
└── RQ3.3: スタック/ヒープ破壊はないか？

RQ4: RefCバックエンド固有の問題か？
├── RQ4.1: 他のバックエンド (JS等) で同じ問題が起きるか？
├── RQ4.2: Idris2コミュニティで既知の問題か？
└── RQ4.3: 最小再現ケースを作成できるか？ ← 次ステップ
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

### 残課題: Bug #2, #3

**有力仮説**:
1. **idris2_predefined_Int64配列の初期化問題**: WASMではstatic配列の初期化が正しく行われない可能性
2. **Value_Int64のアライメント問題**: 32bit WASMで64bitフィールドのアライメントがずれている可能性
3. **idris2_trampolineでクロージャ結果が失われている**: closure dispatch後の結果が正しく返らない

**参考**: https://github.com/shogochiai/idris2-evm-coverage (EVM版トレースツール)

## 優先度別タスク

### P0: 基盤整備（今すぐ必要）
0. ✅ **RefC FFI Bug #1 解決 (2025/01/08)** - [PR #3708](https://github.com/idris-lang/Idris2/pull/3708)
   - `==`, `<`, `>`, `<=`, `>=` 演算子が WASM32 で正常動作
   - Bug #2, #3 は引き続き回避策使用中
1. ✅ 削除されたSPEC.tomlの復活 (2025/01/07完了)
2. `lazy evm ask` のstub解除
3. `lazy dfx ask` のstub解除

### P1: lifecycle統合
1. `lazy evm-lifecycle ask` 実装
2. `lazy dfx-lifecycle ask` 実装
3. `mc deploy/upgrade` の実働化
4. `dfx deploy` 連携
5. Auditor自動割当て

### P2: Self-Amending基盤
1. Futarchy予測市場コントラクト
2. Claude Skillsオンチェーンアクセス
3. AI Agent監視ループ

### P3: 本番運用
1. マルチチェーン対応
2. Threshold ECDSA
3. 自動淘汰メカニズム
