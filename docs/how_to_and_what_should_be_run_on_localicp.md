# ローカル ICP での OUC 実行ガイド

## 概要

OUC (Optimistic Upgrader Canister) をローカル ICP 環境で実行する手順と仕組みを説明します。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                    ビルドパイプライン                         │
├─────────────────────────────────────────────────────────────┤
│  Idris2 ソース  →  RefC  →  C コード  →  Emscripten  →  WASM │
│  (src/*.idr)      backend   (main.c)     (emcc)      (ouc.wasm)
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    WASI スタブ処理                           │
├─────────────────────────────────────────────────────────────┤
│  ouc.wasm  →  wasm2wat  →  sed (WASI除去)  →  wat2wasm      │
│                                               (ouc_stubbed.wasm)
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    ローカル ICP デプロイ                      │
├─────────────────────────────────────────────────────────────┤
│  dfx start  →  dfx deploy  →  dfx canister call             │
│  (レプリカ起動)  (WASM配置)    (クエリ/アップデート)           │
└─────────────────────────────────────────────────────────────┘
```

## 前提条件

### 必要なツール

| ツール | バージョン | インストール方法 |
|--------|-----------|-----------------|
| Idris2 | 0.8.0 | `pack install-deps ouc.ipkg` |
| Emscripten | 4.0+ | `brew install emscripten` |
| wabt | 1.0+ | `brew install wabt` |
| dfx | 0.30+ | `DFXVM_INIT_YES=1 sh -c "$(curl -fsSL https://internetcomputer.org/install.sh)"` |

### 環境変数

```bash
# dfx を使う前に必ず実行
source "$HOME/Library/Application Support/org.dfinity.dfx/env"
```

## 手順

### 1. WASM ビルド

```bash
cd /Users/bob/code/idris2-ouc

# Idris2 → C → WASM
./scripts/build-canister.sh
```

**出力ファイル:**
- `build/ouc.wasm` - WASI インポート付き (ICP では動かない)
- `build/ouc_stubbed.wasm` - WASI スタブ済み (ICP 用)

### 2. WASI スタブ (手動で行う場合)

ビルドスクリプトが失敗した場合の手動手順:

```bash
cd build

# WASM → WAT (テキスト形式)
wasm2wat ouc.wasm -o ouc.wat

# WASI インポートをスタブ関数に置換
sed -e 's|(import "wasi_snapshot_preview1" "fd_close" (func (;3;) (type 1)))|(func (;3;) (type 1) (param i32) (result i32) i32.const 0)|' \
    -e 's|(import "wasi_snapshot_preview1" "fd_write" (func (;4;) (type 5)))|(func (;4;) (type 5) (param i32 i32 i32 i32) (result i32) i32.const 0)|' \
    -e 's|(import "wasi_snapshot_preview1" "fd_seek" (func (;5;) (type 7)))|(func (;5;) (type 7) (param i32 i64 i32 i32) (result i32) i32.const 0)|' \
    ouc.wat > ouc_stubbed.wat

# WAT → WASM
wat2wasm ouc_stubbed.wat -o ouc_stubbed.wasm
```

### 3. ローカル ICP 起動

```bash
# dfx 環境読み込み
source "$HOME/Library/Application Support/org.dfinity.dfx/env"

# ローカルレプリカ起動 (--clean で既存状態をクリア)
dfx start --clean --background
```

### 4. Canister デプロイ

```bash
dfx deploy ouc --network local --no-wallet
```

**成功時の出力例:**
```
Deployed canisters.
URLs:
  Backend canister via Candid interface:
    ouc: http://127.0.0.1:4943/?canisterId=...&id=...
```

### 5. Canister 呼び出しテスト

```bash
# Query メソッド (読み取り専用、即座に返る)
dfx canister call ouc getVersion --network local
dfx canister call ouc getProposalCount --network local
dfx canister call ouc getAuditorCount --network local
dfx canister call ouc getTreasuryBalance --network local

# Update メソッド (状態変更、コンセンサス必要)
dfx canister call ouc submitProposal '("test proposal")' --network local
dfx canister call ouc registerAuditor '(1000)' --network local
```

### 6. 停止

```bash
dfx stop
```

## なぜ WASI スタブが必要か

### 問題

Emscripten が生成する WASM は WASI (WebAssembly System Interface) をインポートする:

```wat
(import "wasi_snapshot_preview1" "fd_close" ...)
(import "wasi_snapshot_preview1" "fd_write" ...)
(import "wasi_snapshot_preview1" "fd_seek" ...)
```

### ICP の制約

ICP は WASI をサポートしない。許可されるインポートは `ic0` 名前空間のみ:

```wat
(import "ic0" "msg_reply" ...)
(import "ic0" "msg_reply_data_append" ...)
(import "ic0" "debug_print" ...)
```

### 解決策

WASI インポートを「何もしない」スタブ関数に置換:

```wat
;; Before (インポート)
(import "wasi_snapshot_preview1" "fd_close" (func (;3;) (type 1)))

;; After (スタブ関数)
(func (;3;) (type 1) (param i32) (result i32) i32.const 0)
```

## macOS 固有の問題と解決策

### Emscripten ヘッダ競合

**問題:** macOS SDK の C++ ヘッダが Emscripten と競合

```
/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1/availability.h:316: error
```

**原因:** `CPATH` や `CPLUS_INCLUDE_PATH` が macOS SDK を指している

**解決:** emcc 実行時に環境変数をクリア

```bash
CPATH= CPLUS_INCLUDE_PATH= emcc ...
```

### gmp.h not found

**問題:** RefC ランタイムが GMP (GNU Multiple Precision) を要求

**解決:** mini-gmp をダウンロードして使用 (build-canister.sh で自動処理)

## ファイル構成

```
idris2-ouc/
├── src/                    # Idris2 ソース
│   ├── Main.idr           # エントリーポイント
│   ├── OUC/               # OUC コアロジック
│   └── ...
├── build/
│   ├── ouc.wasm           # WASI 付き WASM
│   ├── ouc_stubbed.wasm   # WASI スタブ済み WASM (デプロイ用)
│   ├── ouc.wat            # テキスト形式 (デバッグ用)
│   └── idris/             # Idris2 中間ファイル
├── lib/ic0/           # ICP システムコール C スタブ
├── scripts/
│   └── build-canister.sh  # ビルドスクリプト
├── dfx.json               # dfx 設定
└── can.did                # Candid インターフェース定義
```

## dfx.json 設定

```json
{
  "version": 1,
  "dfx": "0.30.1",
  "canisters": {
    "ouc": {
      "type": "custom",
      "candid": "can.did",
      "wasm": "build/ouc_stubbed.wasm",
      "metadata": [
        { "name": "candid:service" }
      ]
    }
  },
  "networks": {
    "local": {
      "bind": "127.0.0.1:4943",
      "type": "ephemeral"
    }
  }
}
```

## トラブルシューティング

### dfx がバージョンエラーを出す

```bash
# dfx.json の "dfx" バージョンを確認
dfx --version  # インストール済みバージョン
# dfx.json の "dfx" フィールドを一致させる
```

### Canister ID が見つからない

```bash
# Canister を再作成
dfx canister create ouc --network local
dfx deploy ouc --network local
```

### WASM インポートエラー

```
Canister's Wasm module is not valid: Module imports function 'fd_close' from 'wasi_snapshot_preview1'
```

→ WASI スタブが適用されていない。手動スタブ手順を実行。

## 次のステップ

1. **Update メソッドテスト** - `submitProposal`, `registerAuditor` など
2. **StableMemory 永続化確認** - canister アップグレード後もデータが残るか
3. **ICP テストネットデプロイ** - Cycles を取得して `dfx deploy --network ic`
