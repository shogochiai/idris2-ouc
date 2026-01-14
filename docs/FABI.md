# Failure-Aware Build Infrastructure (FABI)

## Self-Amending Protocols' Build Server and its OUC protection

### FR Monads に基づくビルドサーバー仕様と Rebinding 安全性

---

## 要旨（Abstract）

Self-amending Protocols は、制度・共同体・ソフトウェアが自らの規則を更新し続ける能力を持つ計算構造である。しかし現行の設計では、アップグレードそのものよりも、**ビルド環境・鍵管理・運用主体**が Failure Sink と化しやすい。本論文では、Failure-Recovery Monads（FR Monads）の観点から、Self-amending Protocols に固有の**ビルドサーバー仕様**を定義し、Upgrade の安全性と活性を同時に改善する設計原理を提示する。

---

## 1. 問題設定

### 1.1 Self-amending Protocols の前提

Self-amending Protocols とは、状態集合 S と自己改変操作集合 A を持ち、

```
apply : S × A → S
```

が制度内部で定義されているプロトコルである。

重要なのは、**改変の正しさ**ではなく、

* 改変が失敗したとき
* 改変が悪用されたとき
* 改変を実行する主体が消失したとき

に、どのような **Rebinding** が可能かである。

---

### 1.2 ビルド環境という未定義領域

既存研究の多くは、Self-amending Protocols を **オンチェーンの規則更新**として扱う。しかし実際には、アップグレードに投入されるバイトコードは、次の写像を経て生成される：

```
build : C × E → B
```

* C : ソースコード集合
* E : ビルド環境（ツールチェーン・依存・鍵）
* B : バイトコード集合

この E が暗黙・属人的であるとき、**ビルド環境自体が Failure Sink になる**。

---

## 2. 形式的枠組み

### 2.1 Failure-Recovery Monads（再掲）

FR Monads とは、計算を

```
M : X → F(Y)
```

として捉え、Failure を例外ではなく第一級の遷移先として扱う構造である。

---

### 2.2 Failure Sink の定義

Failure の集合を F とするとき、Failure Sink とは

```
Σ ⊆ F
```

であり、次を満たす失敗である：

1. Rebinding が未定義
2. 責任が人格に固定される
3. 再起動手順が存在しない

---

### 2.3 Build-Failure の分類

Self-amending Protocols におけるビルド関連 Failure を次に分解する：

| Failure | 説明 |
|---------|------|
| f_env | ビルド環境汚染（供給網攻撃） |
| f_key | 鍵漏洩・紛失 |
| f_repro | 再現不能ビルド |
| f_ops | 運用主体停止 |

従来、これらは Σ（Failure Sink）に落ちていた。

---

## 3. ビルドサーバー仕様の定義

### 定義 3.1（Failure-Aware Build Server）

Failure-Aware Build Server とは、次の構造を持つ組である：

```
BS = ( E, I, P, R )
```

* E : 固定化されたビルド環境定義
* I : 入力証拠（ソース、lockfile、Docker hash）
* P : ビルド手順（純粋関数として記述）
* R : Rebinding 手続き集合

---

### 定義 3.2（Reproducible Build）

ビルドは再現可能であるとは、

```
∀ e₁, e₂ ∈ E, build(c, e₁) = build(c, e₂)
```

が成立することをいう。

---

### 定義 3.3（n-of-n Build Rebinding）

ビルド結果の採用は、独立した n 個のビルダーによる一致：

```
⋂ᵢ₌₁ⁿ buildᵢ(c) = {b}
```

によってのみ成立する。

---

## 4. 命題

### 命題 4.1（Build Sink の解消）

上記仕様を満たすとき、f_env, f_repro は Σ から除外される。

**理由**：Failure 後の Rebinding（再ビルド・第三者検証）が事前定義されているため。

---

### 命題 4.2（鍵の人格分離）

ビルドサーバーが署名のみを行い、Upgrade 鍵を保持しないとき、

```
f_key は人格結合 Sink にならない
```

---

## 5. 含意

* Self-amending Protocols において、「安全なアップグレード」とは **安全なビルド Rebinding** を意味する。
* トラストレス性は副次的であり、中心は **Failure を Sink に落とさない設計**である。
* 本仕様は、Self-amending Villages の運用基盤として必要十分である。

---

## 6. OUC との関係

FABI と OUC は Failure Sink の責務を明確に分離する：

| Failure | FABI | OUC |
|---------|------|-----|
| f_env (環境汚染) | 主担当 | - |
| f_repro (再現不能) | 主担当 | - |
| f_key (鍵問題) | 部分担当 | 主担当 |
| f_code (悪意コード) | - | 主担当 |
| f_audit (監査不能) | - | 主担当 |
| f_liveness (活性) | 部分担当 | 主担当 |

```
Source Code → [FABI] → Bytecode + Evidence → [OUC] → Protocol State
              ↑ Build Rebinding              ↑ Execution Rebinding
```

---

## 参考文献

* Failure-Recovery Monads (FRC.pdf)
* Self-Amending Protocols.pdf
* AGA Loop.pdf
