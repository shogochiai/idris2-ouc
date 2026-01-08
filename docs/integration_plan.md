# OUC ICP Integration Plan

## テスト戦略: `lazy dfx ask` でゼロを目指す

```
idris2-ouc の品質保証
└── lazy dfx ask (ICP) ← 単一の真実の源
    ├── Canister 動作 (Query/Update)
    ├── ビジネスロジック (WASM上で動作保証)
    ├── StableMemory (永続化)
    └── HttpOutcall (EVM RPC読み取り)

※ 純粋Idrisテスト (Chez Scheme) は開発中の高速フィードバック用
※ 最終的な動作保証は ICP 上の canister call で行う
※ HttpOutcall は ICP の機能。EVM スマコンは不要。
```

## 課題解決ツリー

```
OUC をICP Canisterとして本番稼働させる
├── 1. ビルドパイプライン構築 (✅ 完了)
│   ├── 1.1 idris2-ouc → WASM コンパイル
│   │   ├── RefC backend → Emscripten → WASM
│   │   ├── WASI stubbing (fd_close, fd_write, fd_seek)
│   │   └── 依存関係解決 (idris2-cdk)
│   ├── 1.2 Candid Interface 定義
│   │   ├── Query メソッド (getVersion, getProposalCount, etc.)
│   │   └── Update メソッド (submitProposal, registerAuditor, etc.)
│   └── 1.3 dfx プロジェクト設定
│       ├── dfx.json (v0.30.1)
│       └── ローカルデプロイ確認済
│
├── 2. ステートマシン実装
│   ├── 2.1 チェーン別 OU/OUF 状態管理
│   │   ├── ChainId → (OUState, OUFState) マッピング
│   │   ├── StableMemory 永続化
│   │   └── 状態遷移の原子性保証
│   ├── 2.2 Upgrade申請フロー
│   │   ├── 申請の検証 (validateProposal)
│   │   └── 監査人割り当てトリガー
│   ├── 2.3 監査人Pool管理
│   │   ├── 登録条件 (stake, reputation)
│   │   ├── 選択アルゴリズム (VRF/Commit-Reveal)
│   │   └── 不正検出・排除メカニズム
│   └── 2.4 Reward配分
│       ├── Fee収集
│       ├── 監査完了時の報酬計算
│       └── Treasury管理
│
├── 3. HttpOutcall 実装 (ICP機能として)
│   ├── 3.1 EVM RPC 呼び出し
│   │   ├── eth_call (状態読み取り)
│   │   └── レート制限/リトライ
│   ├── 3.2 複数チェーン対応
│   │   ├── RPC エンドポイント管理
│   │   └── フェイルオーバー
│   └── 3.3 セキュリティ
│       ├── RPC レスポンス検証
│       └── タイムアウト処理
│
├── 4. テストレベル (lazy dfx ask で統合)
│   ├── 4.1 開発用: 純粋Idrisテスト (✅ 52テスト)
│   │   └── Chez Scheme上で高速実行 (動作保証ではない)
│   ├── 4.2 検証用: ローカルICP統合テスト (✅ 基本動作確認)
│   │   ├── dfx deploy → canister call
│   │   ├── Query メソッド呼び出し確認
│   │   └── getVersion, getProposalCount 等
│   └── 4.3 本番用: E2Eシナリオテスト (❌ 未実装)
│       ├── 完全なProposalライフサイクル
│       ├── 状態永続化テスト (upgrade後)
│       └── HttpOutcall統合テスト
│
└── 5. 監査人不正対策
    ├── 5.1 不正行為の定義
    │   ├── 虚偽承認 (脆弱なコードを承認)
    │   ├── 共謀攻撃
    │   └── 遅延攻撃
    ├── 5.2 検出メカニズム
    │   ├── オンチェーン事後検証
    │   └── 他の監査人からの報告
    └── 5.3 制裁メカニズム
        ├── Slashing (stake 没収)
        └── Pool からの永久排除
```

## 現状

| コンポーネント | 状態 | 場所 |
|---------------|------|------|
| FRMonad | ✅ 実装済 | idris2-cdk/src/FRMonad/ |
| ICP API bindings | ✅ 実装済 | idris2-cdk/src/ICP/ |
| OUC ビジネスロジック | ✅ 実装済 | idris2-ouc/src/ |
| 純粋Idrisテスト | ✅ 52テスト (開発用) | src/Integration/Tests/ |
| OUC → WASM ビルド | ✅ ローカル動作確認 | scripts/build-canister.sh |
| WASI stubbing | ✅ 手動/自動対応 | wabt (wasm2wat/wat2wasm) |
| Candid定義 | ✅ MVP版 | can.did |
| dfx.json | ✅ v0.30.1対応 | dfx.json |
| ローカルICPデプロイ | ✅ 動作確認済 | dfx deploy --network local |
| Query メソッド | ✅ 動作確認済 | getVersion → 1 |
| Update メソッド | ⏳ FFI実装済 | registerAuditor/suspendAuditor/reactivateAuditor (ビルド確認待ち) |
| StableMemory | ❌ 未テスト | - |
| HttpOutcall | ❌ 未実装 | - |

## 次のアクション

### Phase 1: ビルドパイプライン (✅ 完了 - 2025/01/07)
- ✅ ローカル WASM ビルド (Emscripten)
- ✅ WASI stubbing (wabt)
- ✅ dfx 0.30.1 インストール
- ✅ ローカル ICP デプロイ成功
- ✅ Query メソッド動作確認

### Phase 2: Update メソッド + 永続化 (⏳ 進行中)

**FFI接続: コマンドディスパッチ方式 (2025/01/07 実装)**

選択: B) ディスパッチ方式 + グローバル変数通信

```
アーキテクチャ:
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ canister_entry.c │────>│   ic0_stubs.c    │────>│    Main.idr      │
│                  │     │                  │     │                  │
│ call_idris2(cmd) │     │ ouc_c_set_arg()  │     │ dispatchCommand  │
│     │            │     │ ouc_get_arg()    │     │     │            │
│     ▼            │     │ ouc_set_result() │     │     ▼            │
│ ouc_c_get_result │     │ ouc_c_get_result │     │ CMD_INIT → init  │
│                  │     │                  │     │ CMD_GET_VER → 1  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

**実装済みコマンド (Query: 0-9):**
- `CMD_INIT (0)`: 状態初期化 → result=1 (success)
- `CMD_GET_VERSION (1)`: バージョン取得 → result=1
- `CMD_GET_PROPOSAL_COUNT (2)`: 提案数取得 → result=N
- `CMD_GET_AUDITOR_COUNT (3)`: 監査人数取得 → result=N

**実装済みコマンド (Update: 10+) - 2026/01/07 追加:**
- `CMD_REGISTER_AUDITOR (10)`: 監査人登録 → result: 1=成功, 0=既存, -1=エラー
- `CMD_SUSPEND_AUDITOR (11)`: 監査人停止 → result: 1=成功, 0=不在, -1=エラー
- `CMD_REACTIVATE_AUDITOR (12)`: 監査人再開 → result: 1=成功, 0=不在, -1=エラー

**変更ファイル:**
- `src/Main.idr`: dispatchCommand, setResult/getArg via %foreign, doRegisterAuditor/doSuspendAuditor/doReactivateAuditor
- `support/ic0/ic0_stubs.c`: ouc_set_result_i32, ouc_get_arg_i32, ouc_c_set_arg_i32, ouc_c_get_result_i32
- `support/ic0/canister_entry.c`: call_idris2(), CMD_* constants, Update methods wired to Idris2

**次のステップ:**
1. ⏳ リモートビルドでWASM生成確認 (進行中)
2. ローカルICPでQuery/Updateメソッドテスト
3. ✅ Update用コマンド追加 (CMD_REGISTER_AUDITOR, CMD_SUSPEND_AUDITOR, CMD_REACTIVATE_AUDITOR)

**残タスク:**
- StableMemory 永続化確認 (canister upgrade 後)
- `lazy dfx ask` でギャップ確認

#### RefC/WASM 既知のバグと回避策 (2026/01/08 発見)

**Bug 1: `==` 演算子が Int に対して正しく動作しない**
```idris
-- これは常に False を返す (WASM では)
let x : Int = 1
if x == 1 then ...  -- ← False になる！
```
回避策: `case` パターンマッチングを使用
```idris
case x of
  1 => ...  -- ← 正しく動作
  _ => ...
```

**Bug 2: IORef が呼び出し間で永続化されない**
```idris
globalStateRef : IORef (Maybe State)
globalStateRef = unsafePerformIO $ newIORef Nothing
```
問題: 各 `__mainExpression_0()` 呼び出しで IORef が再初期化される

回避策: C グローバル変数を使用した状態管理
```c
// ic0_stubs.c
static int32_t ouc_state_initialized = 0;
static int32_t ouc_auditor_count = 0;
```
```idris
-- Main.idr
%foreign "C:ouc_get_auditor_count,libic0"
prim__getAuditorCount : PrimIO Int
```

### Phase 3: E2E シナリオテスト
1. 完全な Proposal ライフサイクル (submit → assign → review → execute)
2. 監査人 Pool 操作 (register → suspend → reactivate)
3. Reward 配分

### Phase 4: HttpOutcall 統合
1. EVM RPC モック
2. 実チェーンテスト (testnet)

## macOS ローカルビルドの注意点

```bash
# Emscripten ヘッダ競合回避
CPATH= CPLUS_INCLUDE_PATH= emcc ...

# WASI スタブ (手動)
wasm2wat ouc.wasm -o ouc.wat
sed -e 's|(import "wasi_snapshot_preview1" ...)|(func ... i32.const 0)|' ...
wat2wasm ouc_stubbed.wat -o ouc_stubbed.wasm
```

詳細: `docs/how_to_and_what_should_be_run_on_localicp.md`

## 依存関係

```
idris2-ouc
├── depends: idris2-cdk (FRMonad, ICP API)
└── tools: Emscripten, wabt, dfx
```

## 将来の改善

### 1. テストの WASM 化
現状の純粋 Idris テスト (Chez Scheme) を WASM/CDK ターゲットに移行し、
実行環境と同じ環境でテストを実行できるようにする。

### 2. `lazy dfx ask` 開発
ICP プロジェクト用のギャップ分析ツールを開発。

```
開発場所: ../lazy/pkgs/LazyDfx/
```

**機能:**
- Candid 定義と実装の整合性チェック
- canister call によるエンドポイント動作検証
- StableMemory 永続化テスト
- HttpOutcall 統合テスト

## 参考資料

- [ICP HTTP Outcalls](https://internetcomputer.org/docs/current/developer-docs/smart-contracts/advanced-features/https-outcalls/)
- [ICP Stable Memory](https://internetcomputer.org/docs/current/developer-docs/smart-contracts/maintain/storage/)
- [Candid Specification](https://github.com/dfinity/candid/blob/master/spec/Candid.md)
