# Idris2 Memory-Intensive Patterns

Idris2 コンパイラが OOM (exit code 137) になるパターンと回避策。

## 1. 型レベル状態機械 (Type-Indexed State Machine)

**問題コード:**
```idris
data ProposalState = SPending | SUnderReview | SApproved | ...  -- 7状態

data ValidTransition : ProposalState -> ProposalState -> Type where
  AssignAuditor : ValidTransition SPending SUnderReview
  ApproveProposal : ValidTransition SUnderReview SApproved
  ...

record ProposalInState (s : ProposalState) where
  constructor MkProposalInState
  proposalId : Nat
  ...

transition : {from, to : ProposalState} ->
             ValidTransition from to ->
             ProposalInState from ->
             ProposalInState to
```

**なぜ重い:**
- `{from, to : ProposalState}` で 7×7 = 49 通りの暗黙引数解決
- GADT `ValidTransition` の制約解決
- パラメータ化レコードのインスタンス生成

**解決策:**
```idris
record Proposal where
  state : ProposalState
  proposalId : Nat
  ...

validateTransition : ProposalState -> ProposalState -> Bool
validateTransition SPending SUnderReview = True
validateTransition SUnderReview SApproved = True
...
validateTransition _ _ = False
```

---

## 2. Existential Wrapper + 多分岐パターンマッチ

**問題コード:**
```idris
data SomeProposal : Type where
  MkPending     : ProposalInState SPending -> SomeProposal
  MkUnderReview : ProposalInState SUnderReview -> SomeProposal
  MkApproved    : ProposalInState SApproved -> SomeProposal
  ... -- 7コンストラクタ

-- 各アクセサで7分岐
someProposalId : SomeProposal -> Nat
someProposalId (MkPending p)     = p.proposalId
someProposalId (MkUnderReview p) = p.proposalId
someProposalId (MkApproved p)    = p.proposalId
... -- 7分岐 × 6関数 = 42回の展開
```

**なぜ重い:**
- 各関数で N 分岐 → N 個の制約生成
- 複数のアクセサ関数 → 制約グラフが N × M に膨張
- `ProposalInState s` が各分岐で異なる型 → 型チェッカが全組み合わせを探索

**解決策:**
```idris
-- 単一レコードに統合
record Proposal where
  state : ProposalState
  proposalId : Nat
  chainId : Nat
  ...

-- パターンマッチ不要
proposalId : Proposal -> Nat
proposalId p = p.proposalId
```

---

## 3. Auto-Implicit Proof

**問題コード:**
```idris
data Positive : Type where
  MkPositive : (n : Nat) -> {auto prf : IsSucc n} -> Positive

data Bounded : (upperBound : Nat) -> Type where
  MkBounded : (value : Nat) -> (0 prf : LTE value upperBound) -> Bounded upperBound
```

**なぜ重い:**
- `{auto prf : ...}` は型チェック時に証明を自動探索
- `LTE value upperBound` は再帰的な証明構造
- 多数の `Bounded` 値を扱うと証明探索が爆発

**解決策:**
```idris
-- ランタイム検証に降格
mkPositive : Nat -> Maybe Nat
mkPositive Z = Nothing
mkPositive n = Just n

mkBounded : Nat -> Nat -> Maybe Nat
mkBounded bound value = if value <= bound then Just value else Nothing
```

---

## 4. 大きな case 式のネスト

**問題コード:**
```idris
dispatch : Command -> State -> Result
dispatch cmd st = case cmd of
  CmdA => case st.fieldA of
    SubA1 => case st.fieldB of ...
    SubA2 => ...
  CmdB => case st.fieldA of ...
  ... -- 深いネスト
```

**解決策:**
- 関数に分割
- `Maybe` モナドで早期リターン

---

## 5. 複雑なインターフェース制約

**問題コード:**
```idris
foo : (Show a, Eq a, Ord a, Functor f, Applicative f, Monad f,
       Traversable t, Foldable t) => ...
```

**解決策:**
- 制約を減らす
- 具体型を使う

---

## 6. 大きな Nat リテラルのパターンマッチ

**問題コード:**
```idris
mkKnownChain : Nat -> KnownChain
mkKnownChain 1        = EthMainnet
mkKnownChain 11155111 = EthSepolia    -- 大きなNat
mkKnownChain 42161    = ArbitrumOne
mkKnownChain 421614   = ArbitrumSepolia
mkKnownChain n        = CustomChain n
```

**なぜ重い:**
- Idris2 は Nat を `Z | S Nat` として表現
- `11155111` へのパターンマッチは 11,155,111 個の `S` コンストラクタを展開
- コンパイル時間が数分～数十分に膨張

**解決策:**
```idris
mkKnownChain : Nat -> KnownChain
mkKnownChain n =
  if n == 1        then EthMainnet
  else if n == 11155111 then EthSepolia
  else if n == 42161    then ArbitrumOne
  else if n == 421614   then ArbitrumSepolia
  else CustomChain n
```

**効果:** コンパイル時間 5分+ → 即時

---

## 7. 大きな単一モジュール

**問題:**
- 500行以上のモジュールはコンパイル時間が指数的に増加
- 依存関係の変更で全体再コンパイル

**解決策:**
- モジュール分割（100-200行/モジュール目安）
- 再エクスポートファサードで互換性維持

```idris
-- OUC/Types/Validated.idr (ファサード)
module OUC.Types.Validated

import public OUC.Types.Validated.Address
import public OUC.Types.Validated.Chain
import public OUC.Types.Validated.Proposal
-- ...
```

---

## 検出方法

```bash
# 個別モジュールをチェック (OOM になるモジュールを特定)
idris2 --check src/Module.idr -p deps --source-dir src

# ファイルサイズで重さを推測
wc -l src/**/*.idr | sort -n | tail -10
```

---

## 実例: idris2-ouc

### Economics/Types.idr

**問題:**
- `NonZero` 型に `{auto prf : IsSucc n}` 使用
- 定数ごとに証明オブジェクト生成
- TTC サイズ: **2.43 MB**（異常に大きい）

**修正:**
```idris
-- Before
data NonZero : Type where
  MkNonZero : (n : Nat) -> {auto prf : IsSucc n} -> NonZero

-- After
data NonZero : Type where
  MkNonZeroInternal : (n : Nat) -> NonZero

unsafeNonZero : Nat -> NonZero  -- 内部用
fromNat : Nat -> Maybe NonZero  -- 外部用
```

**効果:** TTC **2.43 MB → 114 KB** (95%削減)

---

### OUC/Types/Validated.idr

**問題 (修正前):**
- 568 行の単一モジュール
- コンパイル時間: 20分+
- メモリ使用: 1-2 GB

**修正:**
1. 6サブモジュールに分割
2. `Positive`, `Bounded` をランタイム検証に変更
3. `mkKnownChain` のNatパターンマッチをif-elseに変更

**分割後の構造:**
```
OUC/Types/
├── Validated.idr          (5KB, facade)
└── Validated/
    ├── Address.idr        (58KB)
    ├── Chain.idr          (46KB)
    ├── Numbers.idr        (67KB)
    ├── Vote.idr           (21KB)
    ├── Proposal.idr       (122KB)
    └── Signature.idr      (25KB)
```

**効果:** コンパイル時間 **20分+ → 数秒**

---

## 開発環境の推奨

### RAM について

**最低限:** 16-32GB（上記パターンを避ければ快適）

**推奨:** 256GB

理由:
1. **不慮のメモリ爆発を受け切れる** - OOM でプロセスが kill されず、問題箇所を特定しやすい
2. **リファクタリング中の余裕** - 修正過程で一時的にメモリ消費が増えても開発継続可能
3. **試行錯誤の自由度** - 型レベルプログラミングの実験がしやすい

Idris2 の依存型は強力だが、コンパイラのメモリ消費は予測困難。
256GB あれば「まず動かして、後で最適化」というアプローチが取れる。
