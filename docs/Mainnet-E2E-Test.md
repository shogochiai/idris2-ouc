# Mainnet E2E テスト手順

## 概要

OUC Canister の HTTP Outcall 機能を ICP Mainnet で検証する。
ローカルレプリカでは HTTP Outcall に追加設定が必要なため、Mainnet での E2E テストが最も信頼性が高い。

## 前提条件

1. **dfx CLI**: v0.24.3 以上
2. **ICP Cycles**: デプロイ + 呼び出しに必要 (約 0.1 ICP 相当)
3. **Identity 設定**: `dfx identity whoami` で確認

## テスト対象メソッド

| メソッド | 機能 | 期待結果 |
|----------|------|----------|
| `testEthBlockNumber` | eth_blockNumber RPC 呼び出し | ブロック番号 (hex) |
| `getProposalCount` | Proposal 数取得 | Nat |
| `submitProposal` | Proposal 作成 | ID 返却 |

## 手順

### 1. Identity 確認

```bash
dfx identity whoami
dfx identity get-principal
```

### 2. Cycles 確認

```bash
dfx wallet balance --network ic
```

必要な Cycles:
- 初回デプロイ: 約 1T cycles
- メソッド呼び出し: 約 0.1T cycles (HTTP Outcall 含む)

### 3. Mainnet デプロイ

```bash
cd /Users/bob/code/idris2-ouc

# WASM ビルド確認
ls -la build/ouc_stubbed.wasm

# Mainnet デプロイ
dfx deploy --network ic ouc
```

### 4. HTTP Outcall テスト

```bash
# eth_blockNumber 呼び出し
dfx canister call --network ic ouc testEthBlockNumber

# 期待結果 (例)
# {"status":"success","result":"0x1234567"}
```

### 5. Storage 永続化テスト

```bash
# Proposal 作成
dfx canister call --network ic ouc submitProposal '(record { selector = "0x12345678"; newImpl = "0x..." })'

# カウント確認
dfx canister call --network ic ouc getProposalCount
```

## HTTP Outcall の注意点

### RPC エンドポイント

現在のデフォルト RPC:
- `https://eth.llamarpc.com` (無料、レート制限あり)

Mainnet では以下の点に注意:
1. **レート制限**: 連続呼び出しで 429 エラーの可能性
2. **タイムアウト**: HTTP Outcall は 30 秒タイムアウト
3. **コスト**: 各 HTTP 呼び出しに Cycles 消費

### エラーハンドリング

```json
// 成功
{"status":"success","result":"0x..."}

// RPC エラー
{"status":"rpc_error","error":"..."}

// タイムアウト
{"status":"timeout"}

// HTTP Outcall 拒否
{"error":"http_request_rejected"}
```

## 検証チェックリスト

- [ ] dfx identity 設定済み
- [ ] Cycles 残高十分
- [ ] WASM ビルド最新
- [ ] Mainnet デプロイ成功
- [ ] testEthBlockNumber 成功
- [ ] submitProposal 成功
- [ ] getProposalCount 永続化確認

## トラブルシューティング

### "Replica not reachable"

Mainnet 接続を確認:
```bash
dfx ping --network ic
```

### "Cycles insufficient"

Cycles をトップアップ:
```bash
dfx wallet send --network ic <canister-id> <cycles>
```

### "HTTP Outcall failed"

1. RPC エンドポイントの可用性確認
2. 別の RPC エンドポイントに切り替え
3. タイムアウト設定の調整

## 結果記録

テスト実行日時: ______

| テスト | 結果 | 備考 |
|--------|------|------|
| testEthBlockNumber | | |
| submitProposal | | |
| getProposalCount | | |
