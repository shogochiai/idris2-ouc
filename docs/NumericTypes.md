# Numeric Types Across Backend Layers

This document summarizes numeric type conventions in the idris2-* ecosystem.

## Package Overview

| Package | Target | Primary Numeric Type |
|---------|--------|---------------------|
| idris2-yul | EVM (Solidity/Yul) | `Integer` |
| idris2-wasm | WASM (IC) | TBD (minimal impl) |
| idris2-cdk | IC Runtime | `Bits64` (via Candid) |
| idris2-ouc | IC Canister | `Integer` |
| idris2-ouf | EVM Contracts | `Integer` (via idris2-yul) |

## idris2-yul

### EVM.Primitives

All FFI operations use `Integer` (arbitrary precision):

```idris
sload : Integer -> IO Integer
sstore : Integer -> Integer -> IO ()
caller : IO Integer
callvalue : IO Integer
```

**Rationale**: EVM uses 256-bit words. Idris2's `Integer` is arbitrary precision, so it can represent any `uint256` value without overflow.

### EVM.ABI.Types

Type descriptors for ABI encoding:

```idris
data ABIType
  = ABI_Uint256    -- uint256
  | ABI_Uint128    -- uint128
  | ABI_Uint64     -- uint64
  | ABI_Uint32     -- uint32
  | ABI_Address    -- address (20 bytes)
  | ABI_Bool       -- bool
  | ABI_Bytes32    -- bytes32
  ...
```

These are **type tags**, not actual value types. Used for:
- ABI JSON generation
- Function signature computation
- Type documentation

### Key Points

1. **No native uint256 type** - Uses `Integer` at runtime
2. **Type safety via tags** - `ABIType` describes structure, doesn't enforce bounds
3. **FFI boundary** - `%foreign "evm:..."` maps to Yul operations

## idris2-cdk (IC Runtime)

### ICP.Candid.Types

Candid type system with actual value types:

```idris
data CandidValue
  = CNat64 Bits64      -- nat64
  | CInt64 Int64       -- int64
  | CNat Nat           -- nat (unbounded)
  | CInt Integer       -- int (unbounded)
  ...

data CandidType
  = CtNat64            -- type tag
  | CtInt64
  | CtNat
  | CtInt
  ...
```

### Candidable Interface

```idris
interface Candidable a where
  candidType : CandidType
  toCandid : a -> CandidValue
  fromCandid : CandidValue -> Maybe a

-- Built-in instance
Candidable Bits64 where
  candidType = CtNat64
  toCandid b = CNat64 b
  fromCandid (CNat64 b) = Just b
  fromCandid _ = Nothing
```

### Key Points

1. **Bits64 for tokens** - ICRC-1 amounts, cycles, timestamps
2. **Nat is Peano** - Avoid for large values (extremely slow)
3. **Integer for unbounded** - JSON parsing, intermediate calculations

## idris2-ouc (This Package)

### Economics Module Convention

All financial values use `Integer` (arbitrary precision):

```idris
-- Treasury.idr
record Treasury where
  ckEthBalance   : Integer   -- ckETH in wei (full precision)
  icpBalance     : Integer   -- ICP in e8s
  operatingRatio : Integer   -- percentage

-- CyclesMinting.idr
record MintingRequest where
  ckEthAmount : Integer
  expectedIcp : Integer
  minIcp      : Integer
```

### Why Integer?

1. **Full precision** - No truncation for any amount
2. **EVM compatibility** - Can hold full `uint256` values
3. **Candid compatibility** - Maps to `nat`/`int`
4. **RefC dependency** - IC WASM uses Emscripten/RefC, so GMP is available
5. **Performance** - GMP is fast (not Peano Nat)

### Trade-off vs Bits64

| Aspect | Integer | Bits64 |
|--------|---------|--------|
| Range | Unlimited | 2^64 |
| Speed | GMP (fast) | Native (fastest) |
| Memory | Variable | Fixed 8 bytes |
| Candid | `nat`/`int` | `nat64` |

For most IC applications, `Bits64` would suffice. We chose `Integer` for:
- Full EVM `uint256` compatibility
- No truncation concerns for ckETH amounts

## Cross-Chain Type Boundaries

```
EVM (idris2-ouf)          Bridge              ICP (idris2-ouc)
─────────────────────────────────────────────────────────────
uint256 (Integer)    →    JSON     →    Integer (parse)
                                           ↓
                                        Integer (direct use)
                                           ↓
                                        Treasury operations
```

No conversion needed - `Integer` is used throughout.

## Summary

| Context | Type | Notes |
|---------|------|-------|
| EVM FFI | `Integer` | Arbitrary precision, no overflow |
| ABI tags | `ABIType` | Descriptors, not values |
| IC Candid | `Bits64` / `Integer` | `nat64` or `nat` |
| Treasury | `Integer` | Full precision, GMP-backed |
| JSON parse | `Integer` | Direct use, no conversion |
| Peano Nat | Avoid | Only for proofs, not computation |
