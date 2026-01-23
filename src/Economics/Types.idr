||| Economics Type Refinements
|||
||| Smart constructors and validated types for Economics domain.
||| Uses runtime validation with safe constructors.
module Economics.Types

import Data.Nat

%default total

-- =============================================================================
-- NonZero Natural Numbers
-- =============================================================================

||| A natural number that is guaranteed to be non-zero (runtime validated).
||| Use fromNat for safe construction, unsafeNonZero for known constants.
public export
data NonZero : Type where
  MkNonZeroInternal : (n : Nat) -> NonZero

||| Extract the underlying Nat from NonZero
public export
toNat : NonZero -> Nat
toNat (MkNonZeroInternal n) = n

||| Try to create a NonZero from a Nat
public export
fromNat : Nat -> Maybe NonZero
fromNat Z = Nothing
fromNat (S n) = Just (MkNonZeroInternal (S n))

||| Create NonZero from a known constant (UNSAFE: caller ensures n > 0)
||| Module-internal use only for well-known constants.
unsafeNonZero : Nat -> NonZero
unsafeNonZero n = MkNonZeroInternal n

public export
Show NonZero where
  show (MkNonZeroInternal n) = show n

public export
Eq NonZero where
  (MkNonZeroInternal n) == (MkNonZeroInternal m) = n == m

-- =============================================================================
-- Safe Division
-- =============================================================================

||| Safe division that requires NonZero divisor
public export
safeDiv : Nat -> NonZero -> Nat
safeDiv n nz = case toNat nz of
  S k => divNatNZ n (S k) ItIsSucc
  Z   => 0  -- unreachable if constructed properly

||| Safe modulo that requires NonZero divisor
public export
safeMod : Nat -> NonZero -> Nat
safeMod n nz = case toNat nz of
  S k => modNatNZ n (S k) ItIsSucc
  Z   => 0  -- unreachable if constructed properly

-- =============================================================================
-- Percentage (0-100) - Runtime validated
-- =============================================================================

||| A percentage value (0-100), clamped at construction
public export
record Percentage where
  constructor MkPct
  value : Nat

||| Create a Percentage, capping at 100
public export
mkPercentage : Nat -> Percentage
mkPercentage n = MkPct (min n 100)

||| Zero percent
public export
zeroPct : Percentage
zeroPct = MkPct 0

||| Hundred percent
public export
hundredPct : Percentage
hundredPct = MkPct 100

||| Extract value
public export
pctValue : Percentage -> Nat
pctValue p = p.value

public export
Show Percentage where
  show p = show p.value ++ "%"

public export
Eq Percentage where
  p1 == p2 = p1.value == p2.value

public export
Ord Percentage where
  compare p1 p2 = compare p1.value p2.value

-- =============================================================================
-- Positive Natural (> 0)
-- =============================================================================

||| Alias for NonZero with clearer semantics
public export
Positive : Type
Positive = NonZero

||| Check if a Nat is positive
public export
isPositive : Nat -> Bool
isPositive Z = False
isPositive (S _) = True

-- =============================================================================
-- Block Range - Runtime validated
-- =============================================================================

||| A block range (from <= to enforced at construction)
public export
record ValidBlockRange where
  constructor MkBlockRange
  fromBlock : Nat
  toBlock   : Nat

||| Create a block range, swapping if from > to
public export
mkBlockRange : Nat -> Nat -> ValidBlockRange
mkBlockRange from to = if from <= to
  then MkBlockRange from to
  else MkBlockRange to from

||| Get the number of blocks in the range
public export
rangeSize : ValidBlockRange -> Nat
rangeSize range = range.toBlock `minus` range.fromBlock

||| Check if range is empty
public export
isEmptyRange : ValidBlockRange -> Bool
isEmptyRange range = range.fromBlock == range.toBlock

public export
Show ValidBlockRange where
  show r = "[" ++ show r.fromBlock ++ ".." ++ show r.toBlock ++ "]"

public export
Eq ValidBlockRange where
  r1 == r2 = r1.fromBlock == r2.fromBlock && r1.toBlock == r2.toBlock

-- =============================================================================
-- Cycles Amount (with minimum)
-- =============================================================================

||| Cycles amount with a minimum threshold
public export
record CyclesAmount where
  constructor MkCyclesAmount
  amount : Nat
  minRequired : Nat

||| Check if cycles amount is sufficient
public export
isSufficient : CyclesAmount -> Bool
isSufficient c = c.amount >= c.minRequired

||| Get deficit (0 if sufficient)
public export
deficit : CyclesAmount -> Nat
deficit c = if c.amount >= c.minRequired
            then 0
            else c.minRequired `minus` c.amount

||| Get surplus (0 if insufficient)
public export
surplus : CyclesAmount -> Nat
surplus c = if c.amount >= c.minRequired
            then c.amount `minus` c.minRequired
            else 0

public export
Show CyclesAmount where
  show c = show c.amount ++ "/" ++ show c.minRequired ++ " cycles"

-- =============================================================================
-- Well-Known Constants as NonZero
-- =============================================================================

||| Blocks per HTTP call (1000)
public export
blocksPerCallNZ : NonZero
blocksPerCallNZ = unsafeNonZero 1000

||| Seconds per day (86400)
public export
secondsPerDayNZ : NonZero
secondsPerDayNZ = unsafeNonZero 86400

||| Slots per stagger window (12)
public export
slotsPerWindowNZ : NonZero
slotsPerWindowNZ = unsafeNonZero 12

||| Minutes per day (1440)
public export
minutesPerDayNZ : NonZero
minutesPerDayNZ = unsafeNonZero 1440

||| Hundred (for percentage calculations)
public export
hundredNZ : NonZero
hundredNZ = unsafeNonZero 100

-- =============================================================================
-- Helper Functions
-- =============================================================================

||| Calculate percentage from two Nats (capped at 100)
public export
calcPercentage : Nat -> Nat -> Percentage
calcPercentage doneVal totalVal = case fromNat totalVal of
  Nothing => hundredPct  -- 0/0 = 100%
  Just nz => mkPercentage (safeDiv (doneVal * 100) nz)

||| Safe ceiling division
public export
ceilDiv : Nat -> NonZero -> Nat
ceilDiv n nz =
  let base = safeDiv n nz
      remainder = safeMod n nz
  in if remainder == 0 then base else base + 1

||| Check if value is within range (inclusive)
public export
inRange : Nat -> Nat -> Nat -> Bool
inRange low high val = val >= low && val <= high

||| Clamp value to range
public export
clamp : Nat -> Nat -> Nat -> Nat
clamp low high val = min high (max low val)
