# OUC Ecosystem Architecture

Self-Amending Protocol実現のためのエコシステム要素と残タスク。

## OUC vs OU 責務分離 (重要)

```
┌─────────────────────────────────────────────────────────────────┐
│                     OUC (ICP Canister)                           │
│  ─────────────────────────────────────────────────────────────  │
│  責務:                                                           │
│  • OU Registry: 各チェーンのOUアドレス管理                       │
│  • Auditor管理: Auditor ↔ OU(s) 割当て                          │
│  • Dashboard: 複数チェーンのOU状態を集約・可視化                 │
│  • Tx Relay: Threshold ECDSA署名でOUへTx送信                    │
│                                                                  │
│  ※ Auditorから見ると OUC が唯一のインターフェース               │
│  ※ UpgradeProposal は OUC が受けるのではなく OU が受ける        │
└──────────────────────────┬───────────────────────────────────────┘
                           │ 監視 / Auditor署名付きTx送信
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ OU (ETH) │    │OU (ARB)  │    │OU (Base) │
    │ chainId=1│    │chainId=42161│ │chainId=8453│
    └────┬─────┘    └────┬─────┘    └────┬─────┘
         │               │               │
    UpgradeProposal  UpgradeProposal  UpgradeProposal
    (各OUが独立して受付・Vote・Tally・Dictionary更新)
```

### Auditor署名 + OUC リレーパターン

```
Auditor (ブラウザ)
    │
    │ 1. Internet Identity / Passkey で認証
    │ 2. OUC に vote を送信 (Candid call)
    │    vote(proposalId, approve, chainId, ouAddr)
    │
    ▼
OUC (ICP Canister)
    │
    │ 3. caller Principal を検証 (登録済み Auditor か)
    │ 4. 投票を記録
    │ 5. 閾値達成を確認 (n-of-m)
    │ 6. Threshold ECDSA で tx 署名
    │    calldata = OU.executeApproved(proposalId)
    │
    ▼
OU (EVM Contract)
    │
    │ 7. OUC の t-ECDSA 署名を検証
    │ 8. OUC が承認済み → 処理実行
```

| 鍵 | 用途 | 保管場所 |
|---|---|---|
| Auditor Principal | 投票者識別 | Internet Identity (Passkey) |
| OUC Threshold ECDSA | tx 署名 (gas支払) + attestation | ICP subnet |

**利点**:
- Auditor は EVM 秘密鍵不要 (鍵管理簡素化)
- Passkey による安全な認証 (フィッシング耐性)
- OUC が唯一の EVM 接点 (gas 管理一元化)

---

```
OUC Ecosystem
│
├── lazy CLI (~/code/lazy)
│   │
│   ├── [x] lazy core ask          # Idris2 STI Parity分析
│   │
│   ├── EVM側
│   │   ├── [x] lazy evm ask           # EVM契約分析 (完了 2025/01/10 確認)
│   │   │   └── Steps 1-3: LazyCore, Step 4: solc source maps + bytecode tracing
│   │   ├── [x] lazy evm init          # Scaffolding (2025/01/11)
│   │   │   │   ※ スマートコントラクト開発の起点
│   │   │   │   ※ Claude Code Skills が文脈に応じて呼び出し
│   │   │   ├── [x] プロジェクト構造生成
│   │   │   │       └── src/{Functions/, Storages/, Tests/, SPEC.toml}
│   │   │   ├── [x] 初期Schema生成 (テンプレート)
│   │   │   ├── [x] 初期Functions生成 (Core.idr)
│   │   │   └── [x] ipkg自動生成
│   │   └── [x] lazy evm-lifecycle ask # デプロイ/Upgrade助言 (完了 2025/01/10)
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
│   │       └── [x] Auditor割当て推奨 (2025/01/10)
│   │               └── Auditor.recommendFromCompare/recommendFromUpgrade: リスク評価→監査者推奨
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
│   │   ├── [x] examples/ERC7546Proxy.idr  # UCS Proxy (693B runtime, 2025/01/10)
│   │   │       └── selector → Dictionary.getImplementation → DELEGATECALL
│   │   └── [x] Nix derivation (nix/idris2-evm-overlay.nix, 2025/01/11)
│   │           └── idris2-yul binary + TTC library for FABI E2E
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
│   │   ├── [x] Contract状態分析API (2025/01/10)
│   │   │       └── Analysis.idr: takeSnapshot, queryImplementation, addressHasCode
│   │   ├── [x] Upgrade検出API (2025/01/10)
│   │   │       └── UpgradeDetection.idr: detectChanges, detectUpgrades, findZombieReferences
│   │   ├── [x] OptimisticUpgrader (2025/01/11, lazy規約準拠)
│   │   │       ├── Functions/Core.idr: proposeUpgrade, vote, tally
│   │   │       ├── Storages/Schema.idr: Proposal, Vote, AdminState
│   │   │       ├── Storages/Slots.idr: ERC-7201 OU storage slots
│   │   │       ├── Tests/AllTests.idr: SPEC-Test Parity
│   │   │       └── SPEC.toml
│   │   └── [x] Nix derivation (nix/idris2-evm-overlay.nix, e11875f)
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
│   │   ├── lib/ic0/
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
│   │   ├── src/ERC7546/
│   │   │   ├── [x] Dictionary.idr
│   │   │   ├── [x] Upgrade.idr
│   │   │   └── [x] SPEC.toml      # 復活済み (2025/01/07)
│   │   │
│   │   ├── src/FABI/              # 追加 (2025/01/11)
│   │   │   ├── [x] Core.idr       # Build Rebinding 型定義
│   │   │   ├── [x] SPEC.toml      # 51 specs (ENV/HASH/EVID/BUILDER/etc.)
│   │   │   └── [x] Tests/AllTests.idr  # SPEC-Test Parity
│   │   │
│   │   └── src/Governance/        # 追加 (2025/01/11)
│   │       ├── [x] Core.idr       # Governance-by-Observation 型定義
│   │       ├── [x] SPEC.toml      # 55 specs (USAGE/FAIL/HEALTH/QUAR/etc.)
│   │       └── [x] Tests/AllTests.idr  # SPEC-Test Parity
│   │
│   │   ├── src/Economics/         # 追加 (2025/01/14)
│   │   │   │   ※ Fee-to-Cycles: ETH fees → ckETH → ICP → Cycles
│   │   │   │   ※ Integer型使用 (GMP via RefC)
│   │   │   ├── [x] Treasury.idr       # ckETH/ICP残高、70/30分配
│   │   │   ├── [x] CyclesMinting.idr  # Minting状態機械、DEX/CMC連携
│   │   │   ├── [x] SPEC.toml          # 12 specs
│   │   │   └── [x] Tests/FeeToCyclesE2E.idr  # 12/12 PASS (型レベル)
│   │   │
│   │   └── docs/e2e/              # E2Eテストロードマップ (2025/01/14)
│   │       ├── [x] README.md          # 4シナリオ分離、アクター定義
│   │       ├── [x] fee-to-cycles.md   # 12/12 PASS
│   │       ├── [x] http-outcall.md    # Procedure Ready
│   │       ├── [x] threshold-ecdsa.md # Type Ready
│   │       ├── [x] erc7546-upgrade.md # Type Ready
│   │       ├── [x] cketh-bridge.md    # Not Started
│   │       └── [x] mainnet.md         # Not Started
│   │
│   ├── idris2-textdao (~/code/idris2-textdao)
│   │   └── [x] Reference impl     # UCSパターン適用例
│   │
│   ├── idris2-icp-indexer (~/code/idris2-icp-indexer) (2025/01/11)
│   │   │   ※ ICP Canister による分散型 EVM Event Indexer
│   │   │   ※ The Graph + Vercel + PostgreSQL を1 Canister で代替
│   │   │   ※ チェーン非依存: 任意EVMチェーンにIndexerインフラ不要で対応
│   │   │
│   │   ├── [x] Core.idr - Core Types
│   │   │       ├── IndexedEvent: blockNumber, txHash, topics, data
│   │   │       ├── IndexerConfig: chains, contracts, topics filter
│   │   │       └── BlobData: Ethereum Blob 直接格納対応
│   │   │
│   │   ├── [x] Polling.idr - Event Polling
│   │   │       ├── HTTP Outcall: eth_getLogs(fromBlock, toBlock, topics)
│   │   │       ├── Timer: 定期ポーリング (ic0_timer)
│   │   │       └── Cursor管理: lastIndexedBlock per chain
│   │   │
│   │   ├── [x] Storage.idr
│   │   │       ├── Stable Memory: イベントログ永続化 (400GB/canister)
│   │   │       ├── Index: contract/topic → events
│   │   │       └── Blob Storage: 大容量データ直接格納
│   │   │
│   │   ├── [x] Query.idr - Query API
│   │   │       ├── Candid: getEventsByContract, getEventsByTopic
│   │   │       ├── HTTP: REST/JSON endpoint (http_request)
│   │   │       └── Pagination: cursor-based
│   │   │
│   │   ├── [x] SPEC.toml (26 specs) + Tests/AllTests.idr (26 tests)
│   │   │
│   │   ├── [ ] OUC統合 (将来)
│   │   │       ├── OU イベント監視: UpgradeProposed, Executed, etc.
│   │   │       └── Dashboard データソース
│   │   │
│   │   └── [ ] A-Life Economics (2025/01/12 設計)
│   │           ├── Tier: Archive(¥3) / Economy(¥80) / Standard(¥300) / Real-time(¥4,500)
│   │           ├── Perpetual Archive: 0.01 ETH で 80年永続
│   │           ├── Catch-up Sync: 即時復活 (Option A)
│   │           └── 詳細: docs/a-life-economics.md
│   │
│   │   ┌─────────────────────────────────────────────────────────┐
│   │   │ ICP Canister Full-Stack 能力                            │
│   │   ├─────────────────────────────────────────────────────────┤
│   │   │                                                         │
│   │   │ 1. 内部データ (Stable Memory / Heap)                    │
│   │   │    • Auditor Registry, OU Registry                     │
│   │   │    • Proposal状態, 投票状況                             │
│   │   │    • Indexed Events                                     │
│   │   │                                                         │
│   │   │ 2. HTTP Outcall (任意のHTTPS通信)                       │
│   │   │    • EVM RPC: eth_getLogs, eth_call, eth_getBalance    │
│   │   │    • Beacon API: Blob取得 (EIP-4844)                   │
│   │   │    • 任意API: CoinGecko, Etherscan, ENS, etc.          │
│   │   │                                                         │
│   │   │ 3. Dashboard 出力 (http_request Query)                  │
│   │   │    • /api/auditors  → JSON: Auditor一覧                │
│   │   │    • /api/ous       → JSON: OU一覧 + チェーン状態      │
│   │   │    • /api/proposals → JSON: Proposal + 投票状況        │
│   │   │    • /api/events    → JSON: Indexed イベント           │
│   │   │    • /dashboard     → HTML: 人間向けUI                 │
│   │   │                                                         │
│   │   │ = バックエンド + DB + API aggregator + HTTPサーバ 一体化│
│   │   └─────────────────────────────────────────────────────────┘
│   │
│   └── idris2-dfx-coverage (~/code/idris2-dfx-coverage)
│       │   ※ WASM coverage 機能を包含 (idris2-wasm-coverage 不要)
│       ├── [x] ic-wasm instrument 連携 (IcWasm/Instrumenter.idr)
│       ├── [x] __get_profiling データ取得 (IcWasm/ProfilingParser.idr)
│       ├── [x] func_id → カバレッジ計算 (CodeCoverage/CodeCoverageAnalyzer.idr)
│       ├── [x] WASM実行トレース収集 (WasmTrace/TraceEntry.idr, TraceParser.idr)
│       ├── [x] PC → Idris2関数マッピング (WasmMapper/WasmFunc.idr, NameSection.idr)
│       ├── [x] IC0 System API モック (Ic0Mock/Ic0Stubs.idr, MockContext.idr)
│       └── [x] HTTP Outcall検出 (IcWasm/HttpOutcallDetector.idr)
│
├── Failure-Aware Build Infrastructure (FABI)
│   │   ※ SPEC.toml + Core.idr + Tests/AllTests.idr 完成 (2025/01/11)
│   │
│   ├── Reproducible Build Spec
│   │   ├── [x] Build environment definition (Docker / Nix / Bazel)
│   │   │       └── BuildEnv, ContainerType, ToolVersion in Core.idr
│   │   ├── [x] Source + lockfile + env hash schema
│   │   │       └── SourceHash, LockfileHash, EnvHash, InputHash, OutputHash
│   │   └── [x] Build evidence format (hash chain)
│   │           └── BuildEvidence, EvidenceChain with previousHash linking
│   │
│   ├── n-of-n Builder Network
│   │   ├── [x] Independent builder roles
│   │   │       └── RegisteredBuilder, BuilderId with stake/baseImage diversity
│   │   ├── [x] Build result intersection protocol
│   │   │       └── BuildConsensus (Pending/Agreed/Disputed), n-of-n requirement
│   │   └── [x] Dispute / mismatch handling
│   │           └── BuildDispute, DisputeResolution, minInvestigationPeriod
│   │
│   ├── Build Rebinding Procedures
│   │   ├── [x] Builder replacement flow
│   │   │       └── ReplacementRequest, ReplacementStatus, capability proving
│   │   ├── [x] Environment migration
│   │   │       └── MigrationRequest, MigrationStatus, backward compat check
│   │   └── [x] Emergency rebuild path
│   │           └── EmergencyBuildRequest, ProvisionalBuild, emergencyTimeout
│   │
│   └── Integration with OUC
│       ├── [x] Build evidence → OUC proposal schema
│       │       └── ProposalBuildAttachment with evidenceHash/sourceHash
│       ├── [x] Auditor build verification tooling
│       │       └── AuditorBuildVerification with rebuildRequested/verified
│       ├── [x] Failure Sink diagnostics (f_env/f_repro/f_key/f_ops)
│       │       └── BuildFailure, RebindingAction, DiagnosticResult
│       └── [x] Nix flake 環境構築 (2025/01/11 完了)
│               ├── [x] idris2 + PR #3708 patch (nix/idris2-overlay.nix)
│               │       └── nixos-unstable, idris2.passthru.unwrapped.overrideAttrs
│               ├── [~] pack (定義あり、hash 未取得)
│               ├── [x] evm-flake (nix/evm-overlay.nix)
│               │       └── [x] foundry 1.5.1 (forge, cast, anvil, chisel)
│               ├── [x] idris2-evm (nix/idris2-evm-overlay.nix)
│               │       ├── [x] idris2-cdk (ICP CDK, FRMonad)
│               │       ├── [x] idris2-yul (Idris2→Yul compiler)
│               │       ├── [x] idris2-subcontract (UCS + OptimisticUpgrader, e11875f)
│               │       └── [x] buildEvmContract (Nix function for E2E)
│               ├── [x] ic-flake (nix/ic-overlay.nix)
│               │       ├── [x] dfx 0.24.3 (binary distribution)
│               │       ├── [x] ic-wasm 0.9.0 (pre-built binary)
│               │       └── [x] didc 2025-12-18 (pre-built binary)
│               └── [x] lazy CLI 依存 (FFI経由)
│                       ├── [x] onnxruntime 1.22.2 (ML推論, STI Parity分析)
│                       └── [x] sqlite 3.51.1 (キャッシュ/インデックス)
│
│   ※ Auditor Verification Flow (E2E)
│   │
│   │   UpgradeProposal
│   │   ├── source: idris2-subcontract / idris2-yul / idris2-evm
│   │   ├── flake.lock (環境固定)
│   │   └── claimed_bytecode_hash (EVM bytecode)
│   │             │
│   │             ▼
│   │   ┌─────────────────────────────────────────────┐
│   │   │ Phase 1: Reproducible Build 検証 (前提)    │
│   │   │   Auditor が Nix + pack build でビルド     │
│   │   │   → ハッシュ一致確認 (不一致なら却下)      │
│   │   └─────────────────────────────────────────────┘
│   │             │ ✓ 一致
│   │             ▼
│   │   ┌─────────────────────────────────────────────┐
│   │   │ Phase 2: 実装監査                          │
│   │   │   ├── 型安全性 (Idris2 証明)               │
│   │   │   ├── ビジネスロジック                     │
│   │   │   └── セキュリティ                         │
│   │   └─────────────────────────────────────────────┘
│   │             │ 監査完了
│   │             ▼
│   │   ┌─────────────────────────────────────────────┐
│   │   │ Phase 3: Vote (OUC経由)                    │
│   │   │   OU登録済み Auditor → OUC canister 投票   │
│   │   │   → n-of-m 承認 → Dictionary 更新          │
│   │   └─────────────────────────────────────────────┘
│   │
│   └── E2E テスト (2025/01/11 検証完了)
│       ├── [x] idris2-yul Nix derivation (nix/idris2-evm-overlay.nix)
│       │       └── 検証済み: Counter.idr → Yul → EVM bytecode
│       │       └── Hash: 236e94b80534a71792e5fb29689893306c7820457da17a6ecaf8b8119c8cb63c
│       ├── [x] 決定論性確認 (同一ソース → 同一ハッシュ)
│       │       └── ビルド2回実行で完全一致確認
│       ├── [x] idris2-subcontract Nix derivation (2025/01/11)
│       │       └── OptimisticUpgrader/* (lazy規約準拠, e11875f)
│       ├── [x] 複数マシンでの再現ビルド検証スクリプト (2025/01/11)
│       │       └── scripts/verify-reproducible-build.sh
│       └── [x] Auditor 監査→投票フロー文書化 (2025/01/11)
│               └── docs/Auditor-Workflow.md: E2E flow diagram
│
├── Self-Amending Protocol Layer
│   │
│   │   ※ 2025/01/11 設計見直し: 二層ガバナンス + OUC Feedback Loop
│   │
│   │   ┌─────────────────────────────────────────────────────────────────┐
│   │   │              Self-Amending Protocol Architecture                 │
│   │   ├─────────────────────────────────────────────────────────────────┤
│   │   │                                                                  │
│   │   │  ┌──────────────┐                                               │
│   │   │  │  Inception   │ ← 人間がテキスト合意で更新 (TextDAO的)        │
│   │   │  │  (語彙注入)   │   IntentKeywords, NonGoals, Boundary          │
│   │   │  └──────┬───────┘                                               │
│   │   │         │ 誘導                                                   │
│   │   │         ▼                                                        │
│   │   │  ┌──────────────┐    ┌─────────────┐                           │
│   │   │  │  LLM観測     │ →  │ Auto-Proposal│                          │
│   │   │  │  (外界情報)   │    │ (Evidence付) │                          │
│   │   │  └──────────────┘    └──────┬──────┘                           │
│   │   │                             │                                    │
│   │   │                             ▼                                    │
│   │   │                      ┌─────────────┐                            │
│   │   │                      │  Auditors   │ ← 3層責務                  │
│   │   │                      │ (検証Gate)  │   Hash/Audit/Inception照合 │
│   │   │                      └──────┬──────┘                            │
│   │   │                             │                                    │
│   │   │                             ▼                                    │
│   │   │                      ┌─────────────┐                            │
│   │   │                      │    OUC      │                            │
│   │   │                      │ (Rebinding) │                            │
│   │   │                      └──────┬──────┘                            │
│   │   │              ┌──────────────┼──────────────┐                    │
│   │   │              ▼              ▼              ▼                    │
│   │   │         Approved      Rejected         Challenged               │
│   │   │              │        (Feedback)       (Freeze)                 │
│   │   │              ▼              │              │                    │
│   │   │          Execute      Re-propose      Resolve                   │
│   │   │                                                                  │
│   │   └─────────────────────────────────────────────────────────────────┘
│   │
│   ├── Inception Layer (人間意思注入点)
│   │   │   ※ 「何を作るか」「何がdriftか」の定義はここでのみ可能
│   │   │   ※ 実装: idris2-subcontract/Inception/* (2025/01/11)
│   │   │
│   │   ├── [x] InceptionSpec 型定義 (Schema.idr)
│   │   │       ├── IntentKeywords: 特徴語彙（LLM提案を誘導）
│   │   │       ├── NonGoals: やらないこと
│   │   │       ├── Boundary: 越えてはいけない線
│   │   │       └── AllowedChangeKinds: 自動提案が触れる領域
│   │   │
│   │   ├── [x] Inception更新プロトコル (Functions/*.idr)
│   │   │       ├── Propose.idr: テキスト提案 → IPFS hash登録
│   │   │       ├── Fork.idr: 既存提案のフォーク (TextDAO的熟議)
│   │   │       ├── Vote.idr: RCV (Ranked Choice Voting)
│   │   │       └── Resolve.idr: 集計・承認・Inception更新
│   │   │
│   │   └── [x] Auto-Adopt Policy (Schema.idr)
│   │           └── AllowedChangeKinds で自動採用可能な変更種別を定義
│   │           └── isAutoAdoptable: ChangeKind → Bool
│   │
│   ├── Auditors (3層責務)
│   │   │
│   │   ├── [x] Layer 1: Hash照合 (Reproducible Build)
│   │   │       └── build(source, env) → claimed_hash と一致確認
│   │   │       └── n-of-n builder agreement
│   │   │       └── 実装: FABI + Nix flake
│   │   │
│   │   ├── [x] Layer 2: 通常監査 (Code Audit)
│   │   │       └── セキュリティ
│   │   │       └── ロジック正当性
│   │   │       └── 型安全性 (Idris2証明)
│   │   │       └── 実装: AuditorPool/Core.idr
│   │   │
│   │   └── [x] Layer 3: Inception照合 (Intent Audit) (2025/01/11, 2025/01/14拡張)
│   │           └── 全A-Life行動がInception語彙と整合するか
│   │           └── 対象: UpgradeProposal, 投票, 出資判断, 重要行動全般
│   │           └── Drift検出 (意図からの逸脱)
│   │           └── AuditorVerdict: Match | DriftDetected | BoundaryViolation
│   │           └── 実装: AuditorPool/InceptionAudit.idr
│   │           └── EscalationDecision: NoEscalation | HumanReview | Reject
│   │           └── FABI管理者不正対策: LLM出力もInception照合で検証
│   │
│   ├── OUC Feedback Loop (2025/01/11 完成)
│   │   │   ※ OUC否決 = Failure Sink ではなく Feedback
│   │   │   ※ Driftはこの層でほぼ消える（採用前に検出）
│   │   │   ※ 実装: OUC/Feedback.idr
│   │   │
│   │   ├── [x] 基本フロー
│   │   │       Proposed → Auditing → Approved/Rejected → Executed/Re-proposed
│   │   │
│   │   ├── [x] Reject = Feedback event
│   │   │       ├── RejectCategory/Severity: 構造化否決理由
│   │   │       ├── FeedbackEvent: 再提案ガイダンス付き
│   │   │       ├── ProposalLineage: 再提案追跡
│   │   │       └── canResubmit, resubmitGuidance
│   │   │
│   │   └── [x] Challenge/Freeze/Resume
│   │           ├── raiseChallenge: 異議申し立て
│   │           ├── freezeProposal: 提案凍結
│   │           ├── resolveChallenge: 解決 (upheld/rejected)
│   │           └── resumeProposal: 再開 (決定反転可能)
│   │
│   ├── AI Agent Infrastructure (LLM Auto-Proposal)
│   │   │   ※ LLMは「生成」のみ。採用判断はAuditors + OUC。
│   │   │
│   │   ├── [x] 外界観測 (ouc-onchain skill)
│   │   │       └── EVM/ICP データ取得
│   │   │       └── Drift検出のための状態監視
│   │   │
│   │   ├── [x] Auto-Proposal生成 (/propose-upgrade command)
│   │   │       └── Inception語彙に誘導されて提案生成
│   │   │       └── Evidence (source_hash, diff_summary, impact) 付与
│   │   │
│   │   ├── [x] 監視ループ (ouc-monitor skill)
│   │   │       └── 外界変化検出 → 提案トリガー
│   │   │       └── Health状態監視
│   │   │
│   │   └── [x] lazy統合 (/check-upgrade command)
│   │           └── Local vs Deployed比較
│   │           └── Pending upgrade検出
│   │
│   └── Governance-by-Observation
│       │   ※ SPEC.toml + Core.idr + Tests/AllTests.idr 完成 (2025/01/11)
│       ├── [x] 使用シグナル収集
│       │       └── UsageSignal, AdoptionMetrics, TimeWindow aggregation
│       ├── [x] 失敗記録（FR semantics）
│       │       └── FailureRecord, FailureType (f_code/f_audit/f_liveness/f_env/f_key)
│       │       └── FailureSeverity, FailureStats, failureRate calculation
│       └── [x] 自動淘汰メカニズム
│               └── ProtocolHealth state machine (Healthy→Wounded→Drifting→Frozen→Dead)
│               └── QuarantineAction, QuarantineRule, shouldQuarantine
│               └── FitnessScore, comparative ranking, bottom percentile flagging
│               └── RetirementProposal flow with governance approval
│
├── External Dependencies
│   │
│   ├── Internet Computer (ICP)
│   │   ├── [x] Canister deployment
│   │   ├── [x] HTTP Outcall
│   │   └── [x] Threshold ECDSA署名 (2025/01/11)
│   │           ├── docs/ThresholdECDSA-Design.md 設計完了
│   │           ├── src/ThresholdECDSA/Core.idr 型定義
│   │           ├── src/ThresholdECDSA/FFI.idr C FFIバインディング
│   │           ├── lib/ic0/threshold_ecdsa.c C実装
│   │           └── SPEC.toml + Tests/AllTests.idr
│   │
│   └── EVM Chains
│       ├── [x] JSON-RPC接続
│       ├── [x] Transaction送信（TxSender）(2025/01/11)
│       │       ├── TxSender/Rlp.idr - EIP-1559 RLPエンコード
│       │       ├── TxSender/Signing.idr - t-ECDSA統合
│       │       └── ThresholdECDSA連携でEVM tx署名
│       └── [x] OU Registry (マルチチェーン管理) (2025/01/11)
│               ├── src/MultiChain/Registry.idr: OU所在チェーン管理
│               ├── ChainId, ChainConfig, ChainRegistry 型
│               ├── SPEC.toml + Tests/AllTests.idr
│               └── ※ Cross-Chain execution は不要 (各OUが独立処理)
│
└── Documentation & Specs
    ├── [x] Self-Amending Protocols.pdf
    ├── [x] FRC.pdf (FR Monad理論)
    ├── [x] AGA Loop.pdf
    ├── [x] SPEC.toml群の復活/再設計 (7ファイル復活済み)
    ├── [x] ClaudeSkills-Spec.md (AI Agent Skills, 2025/01/11)
    ├── [x] FABI.md (Failure-Aware Build Infrastructure)
    ├── [x] OUC-Spec.md (Optimistic Upgrader Canister)
    ├── [x] Auditor-Workflow.md (E2E Auditor Flow, 2025/01/11)
    ├── [x] MultiChain-Design.md (OU Registry設計, 2025/01/11)
    ├── [x] ThresholdECDSA-Design.md (t-ECDSA Signing, 2025/01/11)
    └── [x] a-life-economics.md (A-Life Economics, 2025/01/12)
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
commit = "e11875f"  # OptimisticUpgrader (lazy規約準拠)
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
3. しかし **本体の `lib/ic0/canister_entry.c` は正しく実装されていた**
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

**実装ファイル**: `lib/ic0/canister_entry.c`

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
| Candid レスポンスデコード | P1 | **完了** (2025/01/11) |
| エラーハンドリング強化 | P2 | 未着手 |
| 複数 RPC エンドポイント対応 | P2 | 未着手 |
| Mainnet E2E テスト | P1 | **完了 (2026/01/13)** |

### Mainnet E2E テスト結果 (2026/01/13)

```
dfx canister call ouc testEvmRpc --network ic
→ {"jsonrpc":"2.0","id":1,"result":"0x26dd286"}  ✅

# 0x26dd286 = Block 40,751,750 (Base Mainnet)
# OUC → EVM RPC Canister → Base Mainnet パス完全動作
```

| テスト | 結果 | 備考 |
|--------|------|------|
| `testEthBlockNumber` (直接HTTP Outcall) | ⚠️ コンセンサス失敗 | 各レプリカが異なるブロック番号受信 |
| `testEvmRpc` (EVM RPC Canister経由) | ✅ 成功 | Base Mainnet block 40,751,750 |

**学び**:
- 直接HTTP Outcallで時変データ（ブロック番号等）を取得するとコンセンサス失敗
- EVM RPC Canister経由なら安定（内部でコンセンサス処理済み）
- 本番運用ではEVM RPC Canister使用を推奨

**Candid レスポンスデコード実装内容** (canister_entry.c):
- `parse_leb128_at()`: LEB128パーサ
- `parse_http_response_body()`: HttpResponse Candid record パース
- `extract_jsonrpc_result()`: JSON-RPC結果抽出
- `http_reply_callback()`: 完全なレスポンス処理

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
        │   SPEC format: [[spec]] id="REQ_XXX_NNN" (正規フォーマット移行完了 2025/01/11)
        │
        ├── [x] OUC/SPEC.toml + Tests/CoreTests.idr
        ├── [x] Integration/SPEC.toml + Tests/AllTests.idr (AuditorPool, Rewards, Proposals カバー)
        ├── [x] AuditorPool/SPEC.toml (REQ_POOL_*, Integration tests でカバー)
        ├── [x] Rewards/SPEC.toml (REQ_REW_*, Integration tests でカバー)
        ├── [x] Proposals/SPEC.toml (REQ_PROP_*, Integration tests でカバー)
        ├── [x] HttpOutcall/SPEC.toml + Tests/AllTests.idr (2025/01/11)
        └── [x] ERC7546/SPEC.toml + Tests/AllTests.idr (2025/01/11)
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
└── 参考: lib/ic0/ic0_stubs.c の実装を流用
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
2. ✅ `lazy evm ask` 実装確認 (2025/01/10) - 6-step STI Parity + EVM coverage
3. ✅ `lazy dfx ask` 実装確認 (2025/01/10) - 6-step STI Parity + ICP canister coverage

### P1: lifecycle統合
1. [x] `lazy evm-lifecycle ask` 実装 (完了 2025/01/10)
   - ✅ LazyEvmLifecycle パッケージビルド成功
   - ✅ cast出力パース (storage slot, block number)
   - ✅ Dictionary getImplementation クエリ
   - ✅ queryAllImplementations バッチクエリ
   - ✅ queryDictionaryOwner クエリ
   - ✅ hasCode (zombie reference検出)
   - ✅ Local vs Deployed impl比較 (Compare.compareLocalVsDeployed)
   - ✅ Pending upgrade検出 (Upgrade.detectPendingUpgrades)
   - ✅ Auditor割当て推奨 (Auditor.recommendFromCompare/recommendFromUpgrade)
2. ✅ `lazy dfx-lifecycle ask` 実装 (2025/01/10完了)
   - Canister upgrade検出 (local vs deployed hash)
   - Stable memory migration hooks検出
   - Controller権限分析
   - Cycles残高警告
3. [x] idris2-subcontract Upgrade検出API (2025/01/10)
   - ✅ Analysis.idr: Contract状態分析 (takeSnapshot, queryImplementation)
   - ✅ UpgradeDetection.idr: ERC7546 dictionary変更検出 (detectChanges, findZombieReferences)
4. [x] Auditor自動割当て統合 (2025/01/10)
   - ✅ AuditorPool/AutoAssign.idr: リスクベースの自動割当て
   - RiskLevel/Priority型 (LazyEvmLifecycle.Auditor.Recommendと対応)
   - autoAssignAuditors: 推奨パラメータに基づく監査者選出

### P2: Self-Amending基盤
1. [x] **Inception Layer 型定義** (2025/01/11)
   - ✅ idris2-subcontract/Inception/* 完成
   - InceptionSpec, TextProposal, RankedVote, DriftVerdict 型
   - Propose/Fork/Vote/Resolve 関数群
   - SPEC.toml + Tests/AllTests.idr
2. [x] **Auditors Layer 3: Inception照合** (2025/01/11)
   - ✅ AuditorPool/InceptionAudit.idr 完成
   - auditAgainstInception, analyzeDrift, shouldEscalate
   - DriftSeverity, AuditorVerdict, EscalationDecision 型
   - SPEC.toml 16 specs追加
3. [x] **lazy evm init Scaffolding** (2025/01/11)
   - ✅ Evm/Init/Init.idr 完成 (lazy/pkgs/LazyEvm)
   - テンプレート生成: Schema, Core, Tests, SPEC.toml, ipkg
4. [x] Claude Skillsオンチェーンアクセス (2025/01/10)
   - ouc-onchain: EVM/ICP データ取得パターン
   - /check-upgrade: Upgrade状態確認
   - /propose-upgrade: 提案生成・送信
5. [x] AI Agent監視ループ設計 (2025/01/10)
   - ouc-monitor: 監視ループインフラ設計

### P3: 本番運用
1. [x] **OUC Feedback Loop完成** (2025/01/11)
   - ✅ OUC/Feedback.idr 完成
   - RejectCategory/Severity, FeedbackEvent, ProposalLineage
   - Challenge/Freeze/Resume フロー
   - SPEC.toml 15 specs追加
2. [x] **Threshold ECDSA FFI統合** (2025/01/11)
   - ✅ Core.idr: 型定義 (EcdsaCurve, KeyId, DerivationPath, EcdsaSignature, etc.)
   - ✅ FFI.idr: C FFIバインディング + high-level API (signWithEcdsa)
   - ✅ threshold_ecdsa.c: LEB128 + Candid encoding + ic0_call_* 統合
   - ✅ SPEC.toml 20+ specs + Tests/AllTests.idr 19 tests
3. [x] **OU Registry + Auditor Relay** (2025/01/11)
   - ✅ MultiChain/Registry.idr: チェーン管理 (ChainId, ChainConfig, ChainRegistry)
   - ✅ MultiChain/OURegistry.idr: OU追跡 (RegisteredOU, OUStateSnapshot)
   - ✅ MultiChain/AuditorRelay.idr: 署名収集 (AuditorApproval, PendingApprovalCollection)
   - ✅ Default configs: Ethereum, Arbitrum, Base
   - ✅ SPEC.toml 35+ specs + Tests/AllTests.idr 38 tests (all passing)
   - ※ Cross-Chain execution は不要 (各OUが独立処理)
4. [x] **自動淘汰メカニズム** (Governance/Core.idr に実装済み)
   - ✅ FitnessScore: 選択圧 (usage/reliability/adoption/recency)
   - ✅ HealthAssessment: Healthy → Wounded → Drifting → Frozen → Dead
   - ✅ QuarantineRule: Critical failure → 自動 Freeze
   - ✅ RetirementProposal: 90日 Frozen → governance 承認 → Dead

## A-Life Economics (2025/01/14 更新)

Self-Amending Protocol の持続可能な経済設計。

### 経済モデル分割

| ドキュメント | 内容 |
|-------------|------|
| [economics/ouc.md](./economics/ouc.md) | OUC/Indexer の Tier 課金・収益モデル |
| [economics/a-life.md](./economics/a-life.md) | A-Life 自律経済 (責務分離・検証) |

### A-Life 責務分離 (2025/01/14)

```
┌─────────────────┬───────────────────────────────────────┐
│ A-Life (LLM)    │ 開発(lazy ask), DevOps(lazy lifecycle)│
│                 │ 価値提供(CLI-Canister-EVM), 課金      │
├─────────────────┼───────────────────────────────────────┤
│ Owner (Inception)│ 意志, 市場センシング, 自己評価       │
└─────────────────┴───────────────────────────────────────┘

インフラ完備状況:
  開発: lazy ask ✓
  DevOps: lazy evm-lifecycle / lazy dfx-lifecycle ✓
  価値提供: CLI-Canister-EVM ✓
  課金: ckETH/cycles ✓
  意志注入: Inception ✓

結論: インフラは揃っている。あとは動かすフェーズ。
```

### 経済モデル検証 (精査後 2025/01/14)

| 検証項目 | 結果 | 備考 |
|---------|------|------|
| 固定費0% | △ 条件付き | ICP/EVMは0%、定額LLM選択時は$20-200/月 |
| 損益分岐点 | 存在 | ~$30/月 (非常に低い) |
| 利益率70% | ✓ 成立 | 収益$500/月超で収束 |
| 非線形成長 | ✓ 余地あり | LLM固定費はスケール不変 |
| Meme耐性 | 設計中 | 内部留保・生存者設計が必要 |
| 成熟ロードマップ | Stage 1 | Stage 2-3は資本蓄積後 |

### Tier 別料金

| Tier | Sync 頻度 | 月額 | ユースケース |
|------|-----------|------|--------------|
| **Real-time** | 1/分 | ¥4,500 | DEX, MEV |
| **Standard** | 1/15分 | ¥300 | 一般プロトコル |
| **Economy** | 1/時 | ¥80 | 低頻度更新 |
| **Archive** | 1/日 | ¥3 | 休眠プロジェクト |

### Perpetual Archive

```
「一度払えば永久に残る」

0.01 ETH ($25) → 80年分の Archive Tier
0.02 ETH ($50) → Real-time 1ヶ月 + 即時 Catch-up
```

### Tier 昇降システム

```
Archive (休眠)
    ↓  寄付: 0.02 ETH
Real-time 1ヶ月 (即時 Catch-up sync)
    ↓  残高チェック
継続 or Archive に戻る
```

### TheGraph との差別化

| 条件 | 勝者 |
|------|------|
| 1チェーン + 低クエリ | TheGraph (無料) |
| 1チェーン + 高クエリ | **ICP (9倍安い)** |
| マルチチェーン | **ICP (10倍安い)** |
| Perpetual Archive | **ICP only** |
| t-ECDSA 統合 | **ICP only** |

### 固定費 0% モデル (※条件付き)

```
ICP/EVM コスト構造:
  HTTP Outcall : 100% 変動
  Query        : 100% 変動
  Storage      : 100% 変動
  → 固定費率: ほぼ 0%

※ ただし定額制 LLM 選択時は追加の固定費:
  Claude Pro/Max: $20-200/月
  損益分岐点: ~$30/月 (非常に低い)
  $500/月超で利益率 70% に収束

帰結:
  1. 損益分岐点は存在するが非常に低い
  2. スケールダウンリスク低 (損益分岐点が低いため)
  3. 無限スケール可能 (LLM固定費はスケール不変)
  4. 開発者1人で構築・運営可能
```

**詳細**: [LLM コストモデル課題解決ツリー](#llm-コストモデル課題解決ツリー-20250114)

### スケール試算 (バッチ最適化後)

| 規模 | Archive単価 | 月間コスト | 年間利益 | 利益率 |
|------|------------|-----------|----------|--------|
| 1K | ¥3 | ¥50K | ¥1.4M | 70% |
| 10K | ¥0.6 | ¥200K | ¥17M | 70% |
| 100K | ¥0.1 | ¥600K | ¥188M | 70% |
| 1M | ¥0.04 | ¥4.8M | ¥1.9B | 70% |
| 10M | ¥0.036 | ¥48M | ¥19B | 70% |

**利益率一定 = 固定費 0% の証左**

### ビジョン: 無限スケール

```
Phase 1: DeFi (~100K)
Phase 2: あらゆる DAO (~10M)
  - 自治会、マンション理事会
  - カスタム DAO の大衆化
Phase 3: ロボット経済 (~1B+)
  - ロボットの可処分所得
  - 人間-ロボット共存社会のインフラ
```

### 実装優先度

| Phase | タスク | 状態 |
|-------|--------|------|
| P0 | Fee-to-Cycles 型レベル実装 | [x] 完了 (12/12 tests, 2025/01/14) |
| P0 | HTTP Outcall E2E | [ ] Mainnet待ち |
| P0 | t-ECDSA E2E | [ ] Mainnet待ち |
| 1 | Archive Tier + Balance tracking | [x] 完了 (Tier.idr, ProtocolAccount.idr) |
| 1 | Status state machine (ECON-006-008) | [x] 完了 (Status.idr, 10 tests) |
| 2 | 4 Tier + 自動管理 + Catch-up (即時) | [x] 完了 (CatchUpSync.idr, RecoveryOrchestrator.idr, 20 tests) |
| 3 | バッチポーリング最適化 | [x] 完了 (BatchOptimizer.idr, 10 tests) |
| 4 | Dashboard UI | [x] 完了 (4.1-4.6) |
| 5 | OUC Integration | [~] In Progress (5.1, 5.2, 5.3 done) |

### Dashboard UI 課題解決ツリー (idris2-ouc-ui)

**⚠️ データソース設計 (重要)**
```
┌─────────────────────────────────────────────────────────────┐
│ Dashboard UI                                                 │
│       │                                                      │
│       └── ICP Indexer (idris2-icp-indexer) ← 全データ統合   │
│                 │                                            │
│                 ├── EVM Chains (HTTP Outcall)               │
│                 │     • OU Status (block height, sync状態)  │
│                 │     • Proposals (UpgradeProposed events)  │
│                 │     • UpgradeEvents (Approved/Rejected等) │
│                 │                                            │
│                 └── OUC Canister (Canister間呼出)           │
│                       • Auditors (登録・割当)                │
│                       • Subscription/Treasury (課金・残高)   │
└─────────────────────────────────────────────────────────────┘
※ Dashboard は Indexer のみに Query (単一エンドポイント)
※ 横断クエリ可能: "Auditor X の担当OUで UpgradeProposed あるもの"
```

```
Dashboard UI [~] 進行中
│
├── [x] 4.1 Model/View/Update 骨格 (2025/01/15)
│       ├── [x] 型定義: Auditor, OU, Proposal, Event
│       ├── [x] 型定義: Tier, Subscription, Treasury, UpgradeEvent
│       ├── [x] View: 全タブ (Auditors/OUs/Proposals/Events/Economics/Treasury)
│       ├── [x] Update: 全Msg handlers
│       └── [x] SPEC-Test Parity: 29 specs, 54 tests, 84% coverage
│
├── [x] 4.2 ICP Asset Canister Hosting (2025/01/15)
│       ├── [x] dfx.json 設定 (asset canister)
│       ├── [x] pack build → dist/ 出力 (npm run build)
│       └── [x] dfx deploy --network local 動作確認
│
├── [x] 4.3 Internet Identity 認証 (2025/01/15)
│       ├── [x] @dfinity/auth-client 導入 (esbuild bundled)
│       ├── [x] II ログイン/ログアウト UI (View.idr)
│       ├── [x] Principal 取得・表示 (truncated badge)
│       └── [x] AuthState type + 7 new specs/tests
│
├── [x] 4.4 Indexer 拡張 (OUC Sync追加) ← idris2-icp-indexer (2025/01/15)
│       ├── [x] OucSync.idr type definitions
│       ├── [x] SyncState state machine
│       ├── [x] Tier-based sync interval
│       └── [x] 6 SPEC tests
│
├── [x] 4.5 Tier UI (idris2-ouc-ui) (2025/01/15)
│       ├── [x] Tier selection grid (Archive/Economy/Standard/RealTime)
│       ├── [x] changeTier() API endpoint
│       ├── [x] RequestTierChange/TierChangeSuccess/TierChangeFailure Msgs
│       └── [x] 4 tests
│
├── [x] 4.6 Real-time Monitoring (idris2-ouc-ui) (2025/01/15)
│       ├── [x] Polling toggle (Live button)
│       ├── [x] Notification panel + dismiss/clear
│       ├── [x] Event diff detection (detectNewEvents)
│       └── [x] 6 tests
│
└── [ ] 5. OUC Integration
        │
        ├── [x] 5.1 Indexer → OUC Inter-Canister Call (2025/01/15)
        │       ├── [x] 5.1.1 Inter-Canister Call FFI (ouc_call.c)
        │       ├── [x] 5.1.2 OUC Query Implementation (OucSync/FFI.idr)
        │       └── [x] 5.1.3 Sync Timer (Tier-based intervals)
        │
        ├── [x] 5.2 Dashboard → OUC Write Operations (2025/01/15)
        │       ├── [x] 5.2.1 Indexer Write Endpoints (Mutation.idr)
        │       ├── [x] 5.2.2 Auditor Management (register, assign, remove)
        │       └── [x] 5.2.3 OU Registration (register, update chain)
        │
        ├── [x] 5.3 OUC Core Candid API (idris2-ouc) (2025/01/15)
        │       ├── [x] 5.3.1 Candid Interface (can.did + Interface.idr)
        │       ├── [x] 5.3.2 State Management (StableMemory.idr)
        │       └── [x] 5.3.3 Access Control (AccessControl.idr)
        │
        ├── [ ] 5.4 E2E Testing
        │       ├── [ ] 5.4.1 Local dfx Environment
        │       ├── [ ] 5.4.2 Integration Tests
        │       └── [ ] 5.4.3 Failure Scenarios
        │
        └── [ ] 5.5 Production Deployment
                ├── [ ] 5.5.1 Canister Creation
                ├── [ ] 5.5.2 Configuration
                └── [ ] 5.5.3 Monitoring
```

**E2E テスト詳細**: [docs/e2e/README.md](./e2e/README.md)

## E2E テスト課題解決ツリー (2025/01/14)

### 経済モデルから帰納されるテストシナリオ

docs/economics/ から導出したテスト可能なシナリオ。

**検証方法の分類**:
| 方法 | 適用基準 | メリット |
|------|----------|----------|
| **型** | 純粋関数、算術的正しさ | コンパイル時保証、実行不要 |
| **単体** | 状態遷移、mock可能 | 高速、決定的 |
| **E2E** | 外部依存あり | 統合確認 |

**E2E テスト戦略**: [docs/e2e/README.md - Scenario 5](./e2e/README.md#scenario-5-tier-economics-derived-from-docseconomics)

```
出典: economics/ouc.md (Tier システム、Perpetual Archive)
│
│ ┌─────────────────────────────────────────────┐
│ │ 凡例: [型] = 型レベル保証                   │
│ │       [単体] = 単体テスト                   │
│ │       [E2E] = E2Eテスト (外部依存)          │
│ └─────────────────────────────────────────────┘
│
├── ECON-001: Tier 計算テスト [型]
│   │   入力: balance 金額
│   │   期待: 正しい Tier 割当て
│   │
│   │   テストケース:
│   │   - 3B cycles → Archive
│   │   - 80B cycles → Economy
│   │   - 300B cycles → Standard
│   │   - 4500B cycles → RealTime
│   │
│   │   検証: 依存型で閾値をコンパイル時証明
│   │
│   └── [x] 実装: Economics/Tier.idr
│           - calculateAffordableTier: balance → Tier
│           - tierMonthlyCost, tierDailyCost
│           - 8 unit tests (ECON_TIER_001-008)
│
├── ECON-002: 寄付 → アップグレード フロー [単体]
│   │   入力: protocolId, donation amount
│   │   期待: balance 増加、Tier 昇格、Catch-up 発火
│   │
│   │   フロー:
│   │   donate(protocolId, 0.02 ETH)
│   │     → balance += amount
│   │     → newTier = RealTime
│   │     → triggerCatchUpSync()
│   │     → emit TierUpgraded
│   │
│   │   検証: 状態遷移ロジックを mock でテスト
│   │
│   └── [x] 実装: Economics/ProtocolAccount.idr
│           - donate: 残高増加 + Tier再計算
│           - DonationResult with previousTier/newTier
│           - 10 unit tests (ECON_ACCT_001-010)
│
├── ECON-003: 日次 Tier チェック (自動降格) [単体]
│   │   入力: 時間経過、balance 消費
│   │   期待: balance 不足時に自動降格
│   │
│   │   フロー:
│   │   dailyTierCheck()
│   │     → balance < dailyCost
│   │     → downgrade to affordable tier
│   │     → emit TierDowngraded
│   │
│   │   検証: Timer mock で時間進行テスト
│   │
│   └── [x] 実装: Economics/Scheduler.idr + ProtocolAccount.idr
│           - processHeartbeat: 日次デダクション
│           - dailyDeduction: 残高減少 + Tier再計算
│           - 7 unit tests (ECON_SCHED_001-007)
│
├── ECON-004: Catch-up Sync 実行 [E2E]
│   │   入力: monthsArchived, targetTier
│   │   期待: 正しいコスト計算、sync 完了
│   │
│   │   計算式:
│   │   blocksToSync = monthsArchived * 30 * 24 * 60 * 5
│   │   callsNeeded = blocksToSync / 1000
│   │   cyclesCost = callsNeeded * 500_000_000
│   │
│   │   例: 6ヶ月 → 22B cycles
│   │
│   │   外部依存: External Indexer (HTTP Outcall)
│   │
│   ├── [x] 型レベル: HttpOutcall/CatchUpSync.idr
│   │       - calcBlocksToSync, calcCallsNeeded, calcCatchUpCost
│   │       - CatchUpRequest state machine (Pending→InProgress→Completed)
│   │       - 10 unit tests (ECON_CATCHUP_001-010)
│   └── [ ] E2E: 同期後のブロック番号確認
│
├── ECON-005: Perpetual Archive 年数計算 [型]
│   │   入力: ETH amount
│   │   期待: 正しい年数計算
│   │
│   │   計算式:
│   │   0.001 ETH → 8年
│   │   0.01 ETH → 80年
│   │   0.1 ETH → 800年
│   │
│   │   検証: 算術的正しさを型で証明
│   │
│   └── [x] 実装: Economics/Tier.idr
│           - calculateArchiveYears: balance → years
│           - calculateMonthsAtTier: balance × tier → months
│
├── ECON-006: Archive 状態での Cycles 枯渇 [E2E]
│   │   入力: Archive Tier + cycles = 0
│   │   期待: SUSPENDED 状態に遷移
│   │
│   │   重要: ETH 残高があっても cycles 枯渇で停止
│   │   Archive Tier でも storage/heartbeat に cycles 必要
│   │
│   │   外部依存: ICP runtime (実際の cycles 消費)
│   │
│   ├── [x] 型レベル: Economics/Status.idr (AccountStatus state machine)
│   │       - checkCyclesAndSuspend: ACTIVE → SUSPENDED
│   │       - 10 unit tests (ECON_STATUS_001-010)
│   └── [ ] E2E: cycles 枯渇後の query/update 挙動
│
├── ECON-007: Archive からの復帰フロー [E2E]
│   │   入力: SUSPENDED 状態 + 寄付
│   │   期待: SUSPENDED → RECOVERING → ACTIVE
│   │
│   │   フロー:
│   │   donate() → Tier昇格 → calcCatchUpCost()
│   │            → startCatchUpSync() → ACTIVE
│   │
│   │   長期 Archive 後: 99000 blocks → ~50B cycles
│   │
│   │   外部依存: External Indexer, ICP runtime
│   │
│   ├── [x] 型レベル: Economics/Status.idr (Recovery state machine)
│   │       - startRecovery: SUSPENDED → RECOVERING
│   │       - updateRecovery: progress tracking
│   │       - completeRecovery: RECOVERING → ACTIVE
│   ├── [x] 統合レベル: Economics/RecoveryOrchestrator.idr
│   │       - initiateRecovery: Status + CatchUp統合
│   │       - processRecoveryBatch: バッチ処理と進捗追跡
│   │       - 10 unit tests (ECON_RECOVERY_001-010)
│   └── [ ] E2E: 状態遷移と同期進捗確認
│
└── ECON-008: Cycles 補充フロー [E2E]
    │   入力: cycles < threshold
    │   期待: ETH → ICP → Cycles 自動変換
    │
    │   フロー:
    │   lowCyclesDetected() → calcNeeded()
    │                      → swapETH→ICP → mintCycles()
    │
    │   外部依存: DEX, CMC (ICP canisters)
    │
    ├── [x] 型レベル: Economics/Status.idr (Top-up triggers)
    │       - shouldTriggerTopUp: watermark-based detection
    │       - calculateTopUpAmount: target computation
    └── [ ] E2E: 自動補充トリガーと変換確認
```

### 既存 E2E シナリオ

```
課題: A-Life Self-Sustaining Loop を E2E で検証する
│
├── Scenario 1: Economics Flow (Fee-to-Cycles)
│   │
│   │   User → ckETH Minter → OUC → DEX → CMC → Cycles
│   │
│   ├── [x] Fee-to-Cycles 型レベル (12/12 tests)
│   └── [ ] ckETH Bridge + DEX + CMC 実E2E
│
├── Scenario 2: Cross-Chain Communication
│   │
│   │   OUC Canister ↔ EVM Chain
│   │
│   ├── [x] HTTP Outcall → EVM RPC (Mainnet検証済み)
│   ├── [ ] t-ECDSA → EVM Tx 送信
│   └── [ ] EVM State Read via OUC
│
├── Scenario 3: Auditor Assignment & Voting
│   │
│   │   OUC → assignAuditors() → OU Contract
│   │   Auditors → vote() → OUC → executeApproved() → OU
│   │
│   └── [~] Type Ready (AuditorPool, MultiChain 実装済み)
│
├── Scenario 4: Upgrade Execution
│   │
│   │   OU Contract → executeUpgrade() → Dictionary
│   │
│   └── [x] ERC7546 Type Ready
│
└── Full E2E: ETH deposit → Cycles → Upgrade
    └── [ ] Not Started
```

**テスト戦略詳細**: [docs/e2e/README.md](./e2e/README.md)

## A-Life 成熟モデル課題解決ツリー (2025/01/14)

```
課題: A-Life の段階的成熟と領域拡大を設計する
│
├── 成熟の原則
│   ├── (1) アセットライトから始まる (物理資産不要)
│   ├── (2) A-Lifeにアクセシブルなものから広がる (API経由)
│   ├── (3) 資本蓄積に応じて領域が拡大
│   └── (4) 物理世界へは最後に進出
│
├── Stage 1: ソフトウェア純粋領域
│   │
│   │   必要資本: ~$30/月
│   │   物理依存: なし
│   │   成熟速度: 最速
│   │
│   ├── [ ] メールサービス自動化
│   ├── [x] SaaSツール (lazy CLI) ← 現在
│   ├── [ ] 軽量DeFi (流動性不要の仲介)
│   ├── [ ] 自治DAO管理 (議事録、投票)
│   └── [ ] コンテンツ生成 (記事、翻訳、要約)
│
├── Stage 2: 計算資源・金融領域
│   │
│   │   必要資本: ~$10K-1M
│   │   物理依存: 間接的 (データセンター)
│   │   前提: Stage 1 からの資本蓄積
│   │
│   ├── [ ] GPU資源運用 (推論サービス)
│   ├── [ ] 分散ストレージノード運営
│   ├── [ ] 資本集約DeFi (レンディング、MM)
│   ├── [ ] スマートコントラクト保険
│   └── [ ] A-Life ポートフォリオ運用
│
├── Stage 3: 物理世界接続
│   │
│   │   必要資本: ~$10M+
│   │   物理依存: 直接的 (ロボット、設備)
│   │   前提: ロボットインターフェース普及
│   │
│   ├── [ ] 自動物流
│   ├── [ ] 工場運営
│   ├── [ ] 自動農場
│   └── [ ] 無人店舗
│
└── 統廃合メカニズム
    │
    ├── [ ] A-Life 間 M&A プロトコル
    │       ├── Inception 整合性判定
    │       ├── veToken 交換比率算定
    │       └── ガバナンス統合
    │
    ├── [ ] アセット移動最適化
    │       ├── Stage 間資本移動
    │       ├── A-Life 間出資
    │       └── 領域間シフト
    │
    └── [ ] 清算・撤退フロー
            └── 不採算 A-Life からの資本回収

タイムライン (推定):
  Stage 1: 2025-2027 (現在)
  Stage 2: 2026-2030
  Stage 3: 2028-2032+ (ロボットインターフェース普及後)
```

**詳細**: [economics/maturity.md](./economics/maturity.md)

## Meme 経済耐性課題解決ツリー (2025/01/14)

```
課題: Meme バブル崩壊後も生存する A-Life を設計する
│
├── バブルサイクル (不可避)
│   │
│   │   技術導入 → 社会的注目 → 過剰期待 → 崩壊 → 実用化
│   │
│   ├── FOMO 駆動要因
│   │   ├── 高利回り広告
│   │   ├── AI 生成コンテンツ
│   │   └── 期待値インフレ
│   │
│   └── 沈静化トリガー
│       ├── 価格崩壊
│       ├── 大型詐欺露見
│       └── 規制介入
│
├── 生存者設計要件
│   │
│   ├── [x] 実価値生産
│   │       └── OUC: 監査・アップグレードの実サービス
│   │
│   ├── [x] 明確な Inception
│   │       └── IntentKeywords, NonGoals, Boundary 定義
│   │
│   ├── [x] 健全ガバナンス
│   │       └── Auditor Pool + n-of-m 承認
│   │
│   └── [ ] 十分な内部留保
│           ├── 6ヶ月分運営費の確保
│           └── 収益の一部を自動積立
│
├── OUC の長期ポジショニング
│   │
│   ├── [x] 信頼性インフラとしての価値
│   │       └── Reproducible Build + Auditor 検証
│   │
│   ├── [ ] バブル期収益の蓄積
│   │       └── Tier 収益 → Treasury 自動積立
│   │
│   └── [ ] 沈静後の寡占ポジション確立
│           └── 生存者統合の受け皿
│
└── 実装タスク
    │
    ├── [ ] Treasury 自動積立ロジック
    │       └── Economics/Treasury.idr 拡張
    │
    ├── [ ] 内部留保モニタリング
    │       └── Dashboard: 運営費何ヶ月分か表示
    │
    └── [ ] 統合受入 API
            └── 他 A-Life からの移行パス
```

**詳細**: [economics/meme.md](./economics/meme.md)

## LLM コストモデル課題解決ツリー (2025/01/14)

```
課題: A-Life 運営の LLM コストを最適化する
│
├── コスト構造の現実
│   │
│   │   ※ ecosystem.md「固定費0%」は ICP/EVM のみの話
│   │   ※ 定額制 LLM 選択時は固定費が発生する
│   │
│   │   定額制LLM選択時:
│   │     固定費 = $20-200/月 (LLM)
│   │     変動費 = ICP + EVM (従量)
│   │
│   │   API従量制LLM選択時:
│   │     固定費 = $0
│   │     変動費 = ICP + EVM + LLM (全て従量)
│   │
│   └── 損益分岐点: ~$30/月 (非常に低い)
│
├── スケール戦略
│   │
│   │   立ち上げ: $20固定 で試行錯誤 (Rate Limit 内)
│   │   成長:     $20固定 + 超過分 API
│   │   大規模:   API従量 (固定費ゼロ回帰)
│   │
│   ├── [ ] LLM 使用量モニタリング
│   │       └── Rate Limit 到達検知
│   │
│   ├── [ ] 動的切替ロジック
│   │       └── 定額 → API フォールバック
│   │
│   └── [ ] コスト最適化レポート
│           └── 月次: 定額 vs 従量の比較
│
├── 非線形成長ドライバー
│   │
│   │   収益 × N → LLM 固定費は同じ → 利益率向上
│   │
│   ├── [x] A-Life 自律開発 (lazy ask)
│   ├── [x] Auditor Pool ネットワーク効果
│   ├── [x] 1 Canister で N チェーン対応
│   └── [ ] CLI → Web/App/IoT 拡張
│
└── 利益率収束
    │
    │   $500/月超で 70% に収束
    │
    └── [ ] 利益率モニタリング Dashboard
            └── 現在の利益率 + 収束予測
```

**詳細**: [economics/a-life.md](./economics/a-life.md)

## マクロ競争環境課題解決ツリー (2025/01/14)

```
課題: A-Life が従来 SaaS を置換する競争優位を確立する
│
├── 競争優位の源泉
│   │
│   │   A-Life 利益率: 60-70%
│   │   従来 SaaS:     10-30%
│   │
│   ├── [x] 人件費ゼロ (LLM 代替)
│   ├── [x] 24/7 稼働 (シフト不要)
│   ├── [x] 即時スケール (人員採用不要)
│   └── [x] 品質保証自動化 (Auditor Pool)
│
├── GPU/LLM コスト低下トレンド
│   │
│   │   GPU 供給増加 → LLM コスト低下
│   │   → A-Life 競争力さらに向上
│   │
│   ├── [ ] コスト低下の自動反映
│   │       └── Tier 料金の動的調整
│   │
│   └── [ ] GPU 中古市場監視
│           └── Stage 2 進出タイミング判定
│
├── 政治経済リスク対策
│   │
│   │   4つの選択肢:
│   │     Exit (撤退)
│   │     Voice (抗議)
│   │     Loyalty (従順)
│   │     Confiscation (没収) ← 第四の選択
│   │
│   ├── [x] 分散インフラ (ICP/EVM)
│   │       └── 単一法域の没収リスク軽減
│   │
│   ├── [x] Threshold ECDSA (鍵分散)
│   │       └── 鍵没収の困難化
│   │
│   └── [ ] 多法域展開
│           └── Canister/OU の地理的分散
│
└── Inception = Capital × Creativity
    │
    │   Owner の役割:
    │     Capital: 初期投資 + 再投資判断
    │     Creativity: 方向性 + 語彙注入
    │
    ├── [x] Inception Layer 型定義
    └── [ ] Inception 品質評価メトリクス
            └── 語彙の明確性スコア
```

**詳細**: [economics/macro.md](./economics/macro.md)

## 経済ドキュメント参照

| ドキュメント | 内容 |
|-------------|------|
| [economics/ouc.md](./economics/ouc.md) | OUC/Indexer Tier 課金・収益モデル |
| [economics/a-life.md](./economics/a-life.md) | A-Life 自律経済・LLM コスト精査 |
| [economics/macro.md](./economics/macro.md) | マクロ競争環境・政治経済分析 |
| [economics/maturity.md](./economics/maturity.md) | A-Life 成熟ステージ (Stage 1-3) |
| [economics/meme.md](./economics/meme.md) | Meme 経済サイクル・生存者設計 |
