# idris2-ouc API & Output Reference

## Overview

OptimisticUpgraderCanister (OUC) - EVM スマートコントラクトアップグレード調整システム

## Candid Interface (`can.did`)

### Query Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getProposal(nat)` | text (JSON) | 提案詳細 |
| `getProposalsByChain(nat)` | text (JSON[]) | チェーン別提案 |
| `getProposalsByStatus(text)` | text (JSON[]) | ステータス別提案 |
| `getAuditor(principal)` | text (JSON) | 監査者詳細 |
| `getActiveAuditors()` | text (JSON[]) | アクティブ監査者一覧 |
| `getAuditors()` | `vec AuditorInfo` | 監査者一覧 (Candid) |
| `getSubscription()` | `opt Subscription` | Tier購読状態 |
| `getTreasury()` | `opt Treasury` | 財務残高 |
| `getProposalCount()` | nat | 提案数 |
| `getAuditorCount()` | nat | 監査者数 |
| `getProtocolBalance(text)` | nat | プロトコル残高 (cycles) |
| `getProtocolTier(text)` | nat | プロトコルTier (0-3) |
| `getProtocolCount()` | nat | 登録プロトコル数 |
| `getVersion()` | nat | プロトコルバージョン |
| `getOwner()` | text | オーナーprincipal |

### Update Methods

| Method | Input | Return | Effect |
|--------|-------|--------|--------|
| `submitProposal(text)` | rationale | JSON | 新規提案作成 |
| `cancelProposal(nat)` | proposal ID | JSON | 提案キャンセル |
| `registerAuditor()` | - | JSON | 監査者登録 |
| `suspendAuditor()` | - | JSON | 監査者停止 |
| `reactivateAuditor()` | - | JSON | 監査者復帰 |
| `assignAuditor(nat, principal)` | proposal, auditor | JSON | 監査者割当 |
| `submitReview(nat, text)` | proposal, decision | JSON | レビュー提出 |
| `prepareExecution(nat)` | proposal ID | JSON | 実行準備 |
| `recordExecution(nat, text)` | proposal, txHash | JSON | 実行記録 |
| `distributeReward(principal, nat)` | auditor, amount | JSON | 報酬配布 |
| `donate(text)` | protocol ID | JSON | cycles寄付 |
| `setTier(Tier)` | tier | opt Subscription | Tier設定 |
| `setAutoRenew(bool)` | enabled | opt Subscription | 自動更新設定 |

## Core Data Types

### Proposal Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ UpgradeProposal                                             │
├─────────────────────────────────────────────────────────────┤
│ id: ProposalId          chainId: ChainId                    │
│ target: EvmAddress      newImpl: EvmAddress                 │
│ ou: EvmAddress          proposer: ICPrincipal               │
│ rationale: String       codeHash: String                    │
│ status: ProposalStatus                                      │
│ assignedAuditors: List AuditorId                            │
│ createdAt/updatedAt/expiresAt: Nat (nanoseconds)            │
└─────────────────────────────────────────────────────────────┘

ProposalStatus = Pending | UnderReview | Approved | Rejected
               | Executed | Expired | Cancelled
```

### Auditor

```
┌─────────────────────────────────────────────────────────────┐
│ Auditor                                                     │
├─────────────────────────────────────────────────────────────┤
│ id: AuditorId           status: AuditorStatus               │
│ reputation: Nat (0-1000)                                    │
│ totalReviews: Nat       approvedCount: Nat                  │
│ rejectedCount: Nat      slashCount: Nat                     │
│ stakedAmount: Nat       registeredAt: Nat                   │
└─────────────────────────────────────────────────────────────┘

AuditorStatus = Active | Suspended | Slashed | Inactive
```

### Review

```
┌─────────────────────────────────────────────────────────────┐
│ Review                                                      │
├─────────────────────────────────────────────────────────────┤
│ proposalId: ProposalId  auditorId: AuditorId                │
│ decision: ReviewDecision                                    │
│ comment: String         timestamp: Nat                      │
│ signature: String                                           │
└─────────────────────────────────────────────────────────────┘

ReviewDecision = ApproveUpgrade | RejectUpgrade String | RequestChanges String
```

## Economics Types (A-Life)

### Tier System

| Tier | Monthly Cost | Sync Interval |
|------|-------------|---------------|
| Archive | 3B cycles (~¥3) | 86400秒 (1日) |
| Economy | 80B cycles (~¥80) | 3600秒 (1時間) |
| Standard | 300B cycles (~¥300) | 900秒 (15分) |
| RealTime | 4.5T cycles (~¥4,500) | 60秒 (1分) |

### Protocol Account

```
┌─────────────────────────────────────────────────────────────┐
│ ProtocolAccount                                             │
├─────────────────────────────────────────────────────────────┤
│ protocolId: EvmAddress  chainId: ChainId                    │
│ balance: Nat (cycles)   currentTier: Tier                   │
│ lastSyncBlock: Nat      lastSyncAt: Nat                     │
│ createdAt: Nat          updatedAt: Nat                      │
│ expiresAt: Maybe Nat                                        │
└─────────────────────────────────────────────────────────────┘
```

### Donation/Deduction Results

```
DonationResult = {
  account: ProtocolAccount
  previousTier/newTier: Tier
  tierUpgraded: Bool
  catchUpCost: Nat
  monthsAtTier: Nat
}

DeductionResult = {
  account: ProtocolAccount
  previousTier/newTier: Tier
  tierDowngraded: Bool
  amountDeducted: Nat
}
```

### Scheduler

```
SchedulerStats = {
  currentDay: Nat
  totalAccounts: Nat
  totalDeductions: Nat
  totalSyncs: Nat
  tierDistribution: TierDistribution
  pendingSyncs: Nat
}

HeartbeatResult = {
  scheduler: SchedulerState
  registry: AccountRegistry
  dailyProcessed: Bool
  accountsProcessed: Nat
  tierChanges: Nat
  syncsDue: List EvmAddress
}
```

## Rewards Types

```
Treasury = {
  balance: Nat
  totalCollected: Nat
  totalDistributed: Nat
}

RewardDistribution = {
  recipientId: AuditorId
  proposalId: ProposalId
  amount: Nat
  reason: String
  distributedAt: Nat
  txRef: String
}
```

## Candid Record Types

```candid
type Tier = variant { Archive; Economy; Standard; RealTime };

type Subscription = record {
  currentTier: Tier;
  expiryDate: nat;
  autoRenew: bool;
};

type Treasury = record {
  ckEthBalance: nat;
  icpBalance: nat;
  cyclesBalance: nat;
};

type AuditorInfo = record {
  auditorId: text;
  principalId: text;
  name: text;
  assignedOUs: vec text;
  status: text;
  reputation: nat;
};
```

## JSON Response Format

```json
{
  "status": "success|error",
  "data": { ... },
  "message": "Optional details"
}

// Economics response
{
  "balance": 1000000000,
  "tier": "Standard",
  "months": 6,
  "catchUpCost": 500000000
}
```

## Module Structure

```
src/
├── Main.idr                    # Entry point, command dispatch
├── OUC/Functions/
│   ├── Core.idr               # Core types
│   ├── Lifecycle.idr          # Proposal state transitions
│   └── Signatures.idr         # VRF/cryptographic signatures
├── Economics/
│   ├── Tier.idr               # Tier enum, costs, intervals
│   ├── ProtocolAccount.idr    # Account state
│   └── Scheduler.idr          # Heartbeat, daily processing
├── AuditorPool/Core.idr       # Auditor pool, selection
├── Rewards/Core.idr           # Treasury, fees, distribution
├── MultiChain/Registry.idr    # Chain definitions
├── HttpOutcall/Core.idr       # HTTP request/response types
└── Candid/EvmRpc.idr          # EVM RPC encoding
```

## Supported Chains

- Ethereum Mainnet (1)
- Sepolia (11155111)
- Base (8453)
- Arbitrum (42161)
