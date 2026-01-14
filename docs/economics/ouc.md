# OUC/Indexer 経済モデル

Self-Amending Protocol の持続可能な経済設計。

## 設計原則

```
「プロトコルは生き物。生まれ、成長し、休眠し、時に復活する」

OUC/Indexer は:
- 活発なプロトコル → 適正価格でサービス提供
- 休眠プロトコル → 最低コストで永続保存
- 復活の可能性 → 寄付で即座に復活可能
```

## コスト構造

### ICP 側 (HTTP Outcall)

```
HTTP Outcall コスト公式:
  total_fee = base_fee + size_fee
  base_fee = (3_000_000 + 60_000 * n) * n
  size_fee = (400 * request_bytes + 800 * max_response_bytes) * n

最適化済み (max_response_bytes = 2KB):
  ~0.5B cycles/call ≈ $0.0007/call
```

### EVM 側 (Base L2)

```
Gas Price: ~0.001 Gwei (2025年現在)
Tx Cost: ~100,000 gas × 0.001 Gwei = 0.0000001 ETH ≈ $0.00025/tx
```

## Tier 別料金

| Tier | Sync 頻度 | 月額 (JPY) | 月額 (USD) | ユースケース |
|------|-----------|-----------|-----------|--------------|
| **Real-time** | 1/分 | ¥4,500 | $29 | DEX, MEV, アクティブ DeFi |
| **Standard** | 1/15分 | ¥300 | $2 | 一般プロトコル |
| **Economy** | 1/時 | ¥80 | $0.5 | 低頻度更新 |
| **Archive** | 1/日 | ¥3 | $0.02 | 休眠プロジェクト |

### マルチチェーン対応

| チェーン数 | Real-time | Standard | Economy | Archive |
|-----------|-----------|----------|---------|---------|
| 1 | ¥4,500 | ¥300 | ¥80 | ¥3 |
| 3 | ¥13,500 | ¥900 | ¥240 | ¥9 |
| 5 | ¥22,500 | ¥1,500 | ¥400 | ¥15 |

## Perpetual Archive モデル

### 概念

```
「一度払えば永久に残る」

TheGraph: 使わなくなったら消える (サブスク型)
ICP:      前払いで永続保存 (Perpetual 型)

→ プロトコルの「デジタル墓標」として IC が最適
```

### 寄付金額 → 持続年数

| 寄付額 | USD | Archive 持続 | Economy 持続 | Standard 持続 | Real-time 持続 |
|--------|-----|-------------|-------------|--------------|----------------|
| 0.001 ETH | $2.5 | 8年 | 3ヶ月 | 1ヶ月 | 2週間 |
| 0.005 ETH | $12.5 | 40年 | 15ヶ月 | 4ヶ月 | 1ヶ月 |
| 0.01 ETH | $25 | 80年 | 30ヶ月 | 8ヶ月 | 2ヶ月 |
| 0.02 ETH | $50 | 160年 | 5年 | 16ヶ月 | **1ヶ月** |
| 0.1 ETH | $250 | 800年 | 25年 | 7年 | 5ヶ月 |

## Tier 昇降システム

### Protocol Balance Account

```
┌─────────────────────────────────────────────────────────┐
│  ProtocolAccount                                        │
├─────────────────────────────────────────────────────────┤
│  protocolId    : String       -- OU contract address   │
│  balance       : Nat          -- Cycles balance        │
│  currentTier   : Tier                                  │
│  lastSyncBlock : Nat                                   │
│  expiresAt     : Maybe Timestamp                       │
└─────────────────────────────────────────────────────────┘

data Tier = Archive | Economy | Standard | RealTime

tierMonthlyCost : Tier -> Nat (cycles)
  Archive  = 3_000_000_000      (¥3)
  Economy  = 80_000_000_000     (¥80)
  Standard = 300_000_000_000    (¥300)
  RealTime = 4_500_000_000_000  (¥4,500)
```

### 寄付 → アップグレード フロー

```
donate(protocolId, amount):
  1. balance += amount
  2. newTier = calculateAffordableTier(balance)
  3. if newTier > currentTier:
       triggerCatchUpSync(lastSyncBlock, latest)  -- 即時
       currentTier = newTier
       expiresAt = now + 30 days
  4. emit TierUpgraded(protocolId, newTier)
```

### 自動 Tier 管理 (Daily Timer)

```
dailyTierCheck():
  for each protocol in registry:
    dailyCost = tierMonthlyCost(currentTier) / 30
    if balance >= dailyCost:
      balance -= dailyCost
    else:
      downgrade to affordable tier
      emit TierDowngraded(protocolId)
```

## Catch-up Sync (即時復活)

### Option A: 即時全取得 (採用)

```
Archive → Real-time 復活時:

例: 6ヶ月間 Archive 後に復活
  - 最後の sync から 43,200 ブロック
  - 43,200 blocks ÷ 1000 = 44 HTTP calls
  - 44 × 0.5B = 22B cycles (~¥30)
  - 数分で完了

メリット:
  ✓ 即座に最新データ利用可能
  ✓ ユーザー体験が良い
  ✓ 復活の意思決定を即座に評価可能

コスト:
  - Catch-up 費用は寄付から自動控除
  - 0.02 ETH 寄付のうち ~¥30 が Catch-up に使用
  - 残り ~¥7,470 が 1ヶ月 Real-time 運用に使用
```

### Catch-up 計算式

```
catchUpCost(monthsArchived, eventsPerBlock):
  blocksToSync = monthsArchived * 30 * 24 * 60 * 5  -- 12秒/block
  callsNeeded = blocksToSync / 1000                  -- 1000 blocks/call
  cyclesCost = callsNeeded * 500_000_000            -- 0.5B cycles/call
  return cyclesCost

例:
  6ヶ月 Archive: ~22B cycles (~¥30)
  1年 Archive:   ~44B cycles (~¥60)
  2年 Archive:   ~88B cycles (~¥120)
```

## 復活ユースケース

### シナリオ: 休眠 DeFi プロトコルの検証復活

```
Timeline:
─────────────────────────────────────────────────────────
2024/01  Protocol X ローンチ、Standard Tier
2024/06  開発停止、Archive Tier に降格
         (0.01 ETH 寄付で 80年分永続化)

2025/01  新チームが興味を持つ
         ↓
         0.02 ETH 寄付で Real-time 1ヶ月復活
         ↓
         Catch-up sync: 6ヶ月分のイベント即時取得 (~3分)
         ↓
         Dashboard で過去6ヶ月の利用状況分析:
           - TVL 推移
           - トランザクション数
           - ユニークユーザー数
           - エラー/Revert 率
         ↓
         「TVL $20K、月間 500 tx、可能性あり」
         ↓
         Standard Tier 継続を決定、追加寄付
─────────────────────────────────────────────────────────
```

## TheGraph との比較

### コスト比較

| シナリオ | TheGraph | ICP Indexer | 勝者 |
|----------|----------|-------------|------|
| 1チェーン, 100K queries/月 | ¥0 (無料) | ¥302 | TheGraph |
| 1チェーン, 1M queries/月 | ¥2,900 | ¥320 | **ICP (9x)** |
| 3チェーン, 1M queries/月 | ¥8,700 | ¥920 | **ICP (9x)** |
| 5チェーン, 1M queries/月 | ¥14,500 | ¥1,520 | **ICP (10x)** |
| 1チェーン, 250M queries/月 | ¥780,000 | ¥9,700 | **ICP (80x)** |

### 機能比較

| 機能 | TheGraph | ICP Indexer |
|------|----------|-------------|
| Event Indexing | ✅ | ✅ |
| GraphQL API | ✅ | ❌ |
| Multi-chain 統合 | ❌ (別 subgraph) | ✅ (1 canister) |
| Threshold ECDSA | ❌ | ✅ |
| Trustless Relay | ❌ | ✅ |
| Perpetual Archive | ❌ | ✅ |
| Tier 昇降 | ❌ | ✅ |

### 差別化ポイント

```
TheGraph と競争しない領域:
  ✗ 単一チェーン + 低クエリ量 → TheGraph 無料枠で十分

ICP Indexer の勝ち筋:
  ✓ マルチチェーン統合 (1 canister で複数チェーン)
  ✓ 高クエリ量 (9-80倍安い)
  ✓ Trustless Execution (t-ECDSA 統合)
  ✓ Perpetual Archive (前払いで永続)
  ✓ 復活可能性 (寄付で即座に復活)
```

## OUC 収益モデル

### 課題: Upgrade 依存の収益いびつ

```
問題:
  - Upgrade 頻度: 年 1-4 回 (成熟プロトコル)
  - 「もう Upgrade しない」選択 → 収益ゼロ
  - TheGraph 無料枠に逃げられる

解決:
  - Upgrade 収益 → Health Monitoring 継続収益
  - 「Upgrade しない」→ Immutability Certificate 発行
  - 休眠プロトコル → Archive Tier で最低収益
```

### ハイブリッド収益モデル

| 収益源 | 対象 | 料金 |
|--------|------|------|
| **Health Monitoring** | 全プロトコル | TVL × 0.01%/年 |
| **Tier 課金** | アクティブプロトコル | ¥80-4,500/月 |
| **Upgrade Fee** | Upgrade 実行時 | $50/upgrade |
| **Immutability Cert** | 凍結プロトコル | $100 一回 |
| **Catch-up Fee** | 復活時 | 実費 (¥30-120) |

### 年間収益試算

```
仮定:
  - 100 プロトコルが利用
  - 70% Archive, 20% Economy/Standard, 10% Real-time
  - 年間 50 Upgrades
  - 10 復活イベント

収益:
  Archive (70)      : 70 × ¥36/年     = ¥2,520
  Economy (15)      : 15 × ¥960/年    = ¥14,400
  Standard (10)     : 10 × ¥3,600/年  = ¥36,000
  Real-time (5)     : 5 × ¥54,000/年  = ¥270,000
  Upgrade Fee (50)  : 50 × ¥7,500     = ¥375,000
  Catch-up (10)     : 10 × ¥50        = ¥500
  ────────────────────────────────────────────────
  合計                                 = ¥698,420/年

コスト (最適化後):
  ICP Cycles        : ~¥50,000/年
  ────────────────────────────────────────────────
  利益              : ~¥648,000/年
```

## 実装優先度

### Phase 1: MVP
- [ ] Archive Tier (1日1回 sync)
- [ ] Balance tracking (Cycles)
- [ ] 寄付受付 (ICP/ETH)

### Phase 2: Tier System
- [ ] 4 Tier 実装
- [ ] 自動 Tier 管理 (Timer)
- [ ] Catch-up Sync (即時)

### Phase 3: Dashboard
- [ ] Protocol 一覧
- [ ] Tier 状態表示
- [ ] 寄付 UI
- [ ] Analytics

### Phase 4: OUC 統合
- [ ] Upgrade Relay
- [ ] Auditor Pool
- [ ] Health Monitoring

## 固定費 0% モデル

### ICP コスト構造の特異性

**注意**: 以下はOUC/Indexer単体のコスト構造。
A-Life運用を含む場合は [a-life.md](./a-life.md) のLLMコスト分析を参照。

```
従来インフラ:
  AWS EC2     : 月額固定 (アイドルでも課金)
  TheGraph    : Indexer ノード維持費
  PostgreSQL  : サーバー費用

ICP:
  HTTP Outcall : 100% 変動 (呼び出しごと)
  Query        : 100% 変動 (クエリごと)
  Storage      : 100% 変動 (使用量ごと)

  → 固定費率: ほぼ 0%
```

### 帰結

1. **損益分岐点が存在しない**: 1プロトコルでも黒字
2. **スケールダウンリスクなし**: 不況時も自動でコスト減少
3. **無限スケール可能**: インフラ投資不要

## スケール試算

| 規模 | 月間コスト | 月間収益 | 年間利益 | 利益率 |
|------|-----------|----------|----------|--------|
| 1K | ¥50K | ¥163K | ¥1.4M | 70% |
| 10K | ¥200K | ¥1.6M | ¥17M | 70% |
| 100K | ¥600K | ¥16M | ¥188M | 70% |
| 1M | ¥4.8M | ¥163M | ¥1.9B | 70% |
| 10M | ¥48M | ¥1.63B | ¥19B | 70% |

**利益率が規模によらず一定** = 固定費 0% の証左

## ビジョン: 無限スケールの需要

```
Phase 1: DeFi プロトコル (~100K)
  - 現在の DeFi エコシステム拡大

Phase 2: あらゆる DAO (~10M)
  - 自治会、マンション理事会、サークル
  - 各 DAO が独自金融機能を持つ
  - カスタム DAO の大衆化

Phase 3: ロボット経済 (~1B+)
  - ロボットが可処分所得を持つ
  - ロボット間の安全保障契約
  - 人間-ロボット共存社会のインフラ

→ ICP の固定費 0% モデルだけが、
  この無限スケールに対応できる
```

## OUC-Indexer 関係

```
OU (EVM) ←────────────→ OUC (ICP)
   │                        │
   │ Upgrade/Governance     │ Indexing/Monitoring
   │                        │
   └──── 導線 ──────────────┘

「OU を使う」→「自ずと ICP Indexer を使う」

OUC = Upgrade Coordinator (ガバナンス)
Indexer = Event Monitoring (監視)

密結合だが役割は分離。
OU 利用が Indexer 利用への自然な導線となる。
```

## 結論

```
OUC/Indexer Economics の核心:

1. 低コストで永続 (Archive ¥0.04/月 @10M規模)
2. 寄付で即座に復活 (Catch-up 即時)
3. 固定費 0% (完全従量課金)
4. 無限スケール (1B+ プロトコル対応可能)
5. 利益率一定 (70% @ any scale)

→ Self-Amending Protocol の「生態系」を支えるインフラ
```

## 関連ドキュメント

- [a-life.md](./a-life.md) - A-Life 自律経済モデル
- [macro.md](./macro.md) - マクロ経済環境と競合分析
- [meme.md](./meme.md) - A-Life ミーム経済 (バブルと沈静化)
- [maturity.md](./maturity.md) - A-Life 成熟モデル (Stage 1-3, AIP Phase 2)
- [../e2e/README.md](../e2e/README.md) - E2E テストロードマップ
- [../ecosystem.md](../ecosystem.md) - エコシステム全体像
