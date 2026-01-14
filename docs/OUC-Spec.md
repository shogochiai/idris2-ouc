# Optimistic Upgrader Canister (OUC)

## A Rebinding-Centric Upgrade Protocol

---

## 要旨（Abstract）

Optimistic Upgrader Canister（OUC）は、Upgrade を意思決定問題ではなく **Failure Routing 問題**として再定義するアップグレード機構である。本論文では、OUC を FR Monads に基づいて形式化し、Upgrade の安全性と活性を「マシな Rebinding を事前に用意する」観点から評価する。

---

## 1. 基本構造

### 定義 1.1（Upgrade 状態）

Upgrade 状態集合を U とし、要素は以下を含む：

* 提案バイトコード
* 証拠（ソース hash、ビルド証明）
* 監査状態
* 実行可否

---

### 定義 1.2（OUC）

OUC とは、次の写像を提供するカニスターである：

```
propose : B → U
audit   : U × A → U
execute : U → S
```

---

## 2. Failure の再分類

OUC は Upgrade Failure を次に分離する：

| Failure | 説明 |
|---------|------|
| f_code | 悪意あるコード |
| f_audit | 監査不能 |
| f_liveness | 実行主体不在 |

---

## 3. Rebinding の定義

### 定義 3.1（Optimistic Rebinding）

OUC における Rebinding とは：

* デフォルトで進行
* 異議があれば停止
* 証拠により再開可能

な遷移である。

---

### 定義 3.2（n-of-n Audit）

Upgrade 実行は、監査人集合 A に対し

```
∀ a ∈ A, a ⊨ match(b, c)
```

が成立したときのみ可能。

ここで：
- b : バイトコード
- c : ソースコード
- match : バイトコードとソースの対応検証

---

## 4. 命題

### 命題 4.1（Upgrade 正義）

OUC による Upgrade は、次の意味で正義的である：

* Failure が人格に固定されない
* 実行主体が代替可能
* 証拠が OSS として残る

---

### 命題 4.2（活性保証）

Etherscan Verify 等の運用鍵を必須としない設計により、

```
f_liveness ∉ Σ (Failure Sink)
```

が成立する。

---

## 5. idris2-ouc 実装との対応

### 5.1 モジュール構成

| 仕様概念 | 実装モジュール |
|----------|----------------|
| propose | src/Proposals/Core.idr |
| audit | src/AuditorPool/Core.idr |
| execute | src/ERC7546/Upgrade.idr |
| Failure routing | FRMonad.Core (idris2-cdk) |

### 5.2 状態遷移

```
src/OUC/Lifecycle.idr で定義:

ProposalState = Pending | Auditing | Approved | Rejected | Executed

状態遷移:
  Pending → Auditing  (監査開始)
  Auditing → Approved (n-of-n 監査完了)
  Auditing → Rejected (異議あり)
  Approved → Executed (実行)
```

### 5.3 Auditor Pool

```
src/AuditorPool/Core.idr:

- registerAuditor   : Principal → FR AuditorId
- suspendAuditor    : AuditorId → FR ()
- reactivateAuditor : AuditorId → FR ()
- getAuditorCount   : FR Nat
```

---

## 6. FABI との関係

OUC は FABI の出力（Bytecode + Evidence）を入力として受け取る：

```
Source Code → [FABI] → Bytecode + Evidence → [OUC] → Protocol State
              ↑ Build Rebinding              ↑ Execution Rebinding
```

### Failure Sink 責務分離

| Failure | FABI | OUC |
|---------|------|-----|
| f_env (環境汚染) | 主担当 | - |
| f_repro (再現不能) | 主担当 | - |
| f_key (鍵問題) | 部分担当 | 主担当 |
| f_code (悪意コード) | - | 主担当 |
| f_audit (監査不能) | - | 主担当 |
| f_liveness (活性) | 部分担当 | 主担当 |

---

## 7. Self-amending Villages への適用

* OUC は「正しいアップグレード」を決めない
* 代わりに「悪い Rebinding を防ぐ」
* これにより、共同体は長期安定と再起動可能性を獲得する

---

## 結論

Self-amending Protocols の核心は、**失敗を消すことではなく、失敗後の結び替えを設計すること**にある。

OUC と Failure-Aware Build Infrastructure は、

> マシな rebinding を先んじて用意することこそが正義である

というイデオロギーを、**実装可能な制度**へ落とす最小構成である。

---

## 参考文献

* Failure-Recovery Monads (FRC.pdf)
* Self-Amending Protocols.pdf
* AGA Loop.pdf
* FABI.md (本リポジトリ)
