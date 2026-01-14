# Project Agent Instructions

## アーキテクチャ概要

**Idris2 マルチターゲット開発環境**

同じIdris2言語でEVMとICPの両方をターゲットにできる:

| リポジトリ | ターゲット | 出力 | 用途 |
|-----------|-----------|------|------|
| **idris2-ouc** | ICP (WASM) | Canister | Optimistic Upgrader Canister - オフチェーン監視・署名 |
| **idris2-ouf** | EVM (bytecode) | Smart Contract | Optimistic Upgrader Frontend - オンチェーンロジック |

### idris2-ouf (EVM) の特徴

`sload`, `sstore`, `caller`, `timestamp`, `mstore`, `log2` などのEVMオペコードを直接Idris2から呼べる:

```idris
-- idris2-ouf/src/Main/Functions/ProposeUpgrade.idr
getProposer : IO Integer
getProposer = sload SLOT_PROPOSER

requireProposer : IO ()
requireProposer = do
  proposer <- getProposer
  callerAddr <- caller
  if proposer == callerAddr
    then pure ()
    else revertConflict AuthViolation
```

### idris2-ouc (ICP) の特徴

ICP System APIを呼び出し、RefCバックエンド経由でWASMにコンパイル:

```idris
-- idris2-ouc/src/Main.idr (canister entry)
main : IO ()
main = do
  cmd <- getCommand
  case cmd of
    Heartbeat => processHeartbeat ...
    Query => handleQuery ...
```

### 連携フロー

```
User → idris2-ouf (EVM) → ETH deposit → ckETH Bridge → idris2-ouc (ICP) → ckETH残高確認
                                                                      ↓
                                                              ProtocolAccount.balance更新
```

---

## 必須ルール (Must Follow)

### Idris2 ICP Canister 開発規約

**新規キャニスタ・モジュール作成時は必ず `lazy dfx init` を使用すること。**

```bash
# 新規キャニスタモジュール作成
lazy dfx init <module_name>

# 開発中の分析・推奨アクション取得
lazy dfx ask <target_dir>
```

これにより:
- SPEC.toml + Core.idr + Tests/AllTests.idr の3点セットが生成される
- lazy規約に準拠した構造になる
- `lazy dfx ask` でSTI Parity分析が可能になる

### ERC-7546 vs ERC-2535

**OUF (../idris2-ouf) は ERC-7546 Upgradeable Clone を使用。ERC-2535 Diamond Standard ではない。**

| 規格 | 関数 | セレクタ |
|------|------|----------|
| ERC-7546 | `getImplementation(bytes4)` | `0xdc9cc645` |
| ERC-2535 | `facetAddress(bytes4)` | `0xcdffacc6` |

OUC から OU を監視する際は `getImplementation` (0xdc9cc645) を使用すること。

## Quick Reference

```bash
# Analyze codebase and get recommended actions
lazy core ask <target_dir>

# Phase 1 (Vibe Bootstrap): Focus on test discovery
lazy core ask <target_dir> --steps=4

# Phase 2 (Spec Emergence): Bidirectional parity
lazy core ask <target_dir> --steps=1,2,3

# Phase 3 (TDVC Loop): Chase Zero Gap, find implicit bugs, and Vibe More
lazy core ask <target_dir> --steps=1,2,3,4
lazy core ask <target_dir> --steps=5
```

## Interpreting Output

- **URGENT** actions: Execute immediately
- **High** priority: Address in current session
- **Medium/Low**: Queue for later

## Policy Mapping

`lazy core ask` converts gaps → signals → recommendations.
Follow recommendations to maintain project health.

## Idris2 Compilation Memory Pitfalls

Idris2 compilation can explode from ~165MB to 16GB+ RAM when:

1. **Type ambiguity** - Same type name in multiple modules (e.g., `HttpResponse` in both FRC and HttpOutcall) causes compiler to backtrack excessively during type inference
2. **Circular dependencies** - Modules in same package with complex interdependencies
3. **Unresolved imports** - Missing or conflicting module imports

**Fix**: Keep packages cleanly separated. idris2-ouc depends on idris2-cdk for FRMonad types. Don't duplicate types across packages.

## RefC Backend Integration (ICP/WASM)

### 不変のルール

**RefC の `__mainExpression_0()` は IO を実行しない。closure を返すだけ。**

```c
// ❌ アンチパターン: closure を捨てる (IO は実行されない!)
(void)__mainExpression_0();

// ✅ 正パターン: trampoline で IO を実行する
typedef void* Value;
extern Value __mainExpression_0(void);
extern Value idris2_trampoline(Value v);

Value closure = __mainExpression_0();
idris2_trampoline(closure);
```

### 本体の実装パターン (lib/ic0/canister_entry.c)

```c
static int32_t call_idris2(int32_t cmd) {
    ouc_reset_ffi();
    ouc_c_set_arg_i32(0, cmd);
    void* closure = __mainExpression_0();
    idris2_trampoline(closure);  // ← 必須!
    return ouc_c_get_result_i32();
}
```

### テスト再現を作る際の禁則

1. **手書きの canister entrypoint を増やすな** - 既存の `lib/ic0/canister_entry.c` を再利用
2. **本体と異なるパターンを使うな** - 差分だけにして、entry は共通化
3. **closure を捨てるな** - `(void)__mainExpression_0()` は常に誤り

### 迅速な切り分けチェック (5分で終わる)

Bug を疑う前に:

1. エントリ関数にログを入れて「その関数が実行されている」ことを証明
2. `closure` の値をログ (null かどうか)
3. FFI 関数が呼ばれたログが出るまで他を疑わない

### なぜこうなっているか

RefC ランタイムは trampoline によって:
- 評価順序の管理
- スタック・tailcall の最適化
- GC との連携

を行う。`__mainExpression_0()` 直接呼び出しではこれらが動作しない。
