# OUC Ecosystem Architecture

Self-Amending Protocol実現のためのエコシステム要素と残タスク。

```
OUC Ecosystem
│
├── lazy CLI (~/code/lazy)
│   ├── [x] lazy core ask          # Idris2 STI Parity分析
│   ├── [ ] lazy evm ask           # EVM契約分析（stub）
│   └── [ ] lazy evm-lifecycle ask # デプロイ/Upgrade助言
│       ├── [ ] Upgrade proposal検出
│       ├── [ ] mc CLI連携
│       └── [ ] Auditor割当て推奨
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
│   │   │   └── [ ] SPEC.toml      # 削除済み、要復活
│   │   │
│   │   ├── src/Rewards/
│   │   │   ├── [x] Core.idr       # 260行、FRMonad準拠
│   │   │   └── [ ] SPEC.toml      # 削除済み、要復活
│   │   │
│   │   ├── src/Proposals/
│   │   │   ├── [x] Core.idr
│   │   │   └── [ ] SPEC.toml      # 削除済み、要復活
│   │   │
│   │   ├── src/HttpOutcall/
│   │   │   ├── [x] Core.idr
│   │   │   ├── [x] EvmRpc.idr
│   │   │   ├── [x] TxSender/
│   │   │   └── [ ] SPEC.toml      # 削除済み、要復活
│   │   │
│   │   └── src/ERC7546/
│   │       ├── [x] Dictionary.idr
│   │       ├── [x] Upgrade.idr
│   │       └── [ ] SPEC.toml      # 削除済み、要復活
│   │
│   └── idris2-textdao (~/code/idris2-textdao)
│       └── [x] Reference impl     # UCSパターン適用例
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
    ├── [ ] SPEC.toml群の復活/再設計
    └── [ ] Claude Skills仕様書
```

## 凡例

- `[x]` 実装済み
- `[~]` 部分実装/テンプレートのみ
- `[ ]` 未実装

## 優先度別タスク

### P0: 基盤整備（今すぐ必要）
1. 削除されたSPEC.tomlの復活
2. `lazy evm ask` のstub解除

### P1: lifecycle統合
1. `lazy evm-lifecycle ask` 実装
2. `mc deploy/upgrade` の実働化
3. Auditor自動割当て

### P2: Self-Amending基盤
1. Futarchy予測市場コントラクト
2. Claude Skillsオンチェーンアクセス
3. AI Agent監視ループ

### P3: 本番運用
1. マルチチェーン対応
2. Threshold ECDSA
3. 自動淘汰メカニズム
