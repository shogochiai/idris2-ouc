||| Numeric Validated Types
module OUC.Types.Validated.Numbers

import Data.List
import Data.List1
import Data.Nat

%default total

-- =============================================================================
-- NonEmpty: Guaranteed non-empty list (like Data.List1 but with more utils)
-- =============================================================================

||| Re-export List1 as NonEmpty for clarity
public export
NonEmpty : Type -> Type
NonEmpty = List1

||| Convert List to NonEmpty, failing if empty
public export
toNonEmpty : List a -> Maybe (NonEmpty a)
toNonEmpty [] = Nothing
toNonEmpty (x :: xs) = Just (x ::: xs)

||| Convert NonEmpty back to List
public export
fromNonEmpty : NonEmpty a -> List a
fromNonEmpty (x ::: xs) = x :: xs

||| Filter non-empty, returns Maybe (might become empty)
public export
filterNonEmpty : (a -> Bool) -> NonEmpty a -> Maybe (NonEmpty a)
filterNonEmpty p ne =
  let filtered = filter p (fromNonEmpty ne)
  in toNonEmpty filtered

||| Sort non-empty list by comparison function
public export
sortNonEmptyBy : (a -> a -> Ordering) -> NonEmpty a -> NonEmpty a
sortNonEmptyBy cmp ne =
  case sortBy cmp (fromNonEmpty ne) of
    [] => ne  -- impossible but needed for totality
    (y :: ys) => y ::: ys

-- =============================================================================
-- Positive: Non-zero natural number (runtime validated)
-- =============================================================================

||| Positive natural number (n >= 1)
public export
data Positive : Type where
  MkPositiveInternal : (n : Nat) -> Positive

||| Smart constructor
public export
mkPositive : Nat -> Maybe Positive
mkPositive Z = Nothing
mkPositive (S n) = Just (MkPositiveInternal (S n))

||| Unsafe constructor for known constants
unsafePositive : Nat -> Positive
unsafePositive n = MkPositiveInternal n

||| Get the underlying value
public export
positiveValue : Positive -> Nat
positiveValue (MkPositiveInternal n) = n

||| Positive is always at least 1
public export
positiveGte1 : Positive -> Nat
positiveGte1 = positiveValue

public export
Show Positive where
  show (MkPositiveInternal n) = show n

public export
Eq Positive where
  (MkPositiveInternal n) == (MkPositiveInternal m) = n == m

public export
Ord Positive where
  compare (MkPositiveInternal n) (MkPositiveInternal m) = compare n m

-- =============================================================================
-- Bounded: Value with upper bound (runtime validated)
-- =============================================================================

||| Value bounded by a maximum (runtime validated)
public export
record Bounded (upperBound : Nat) where
  constructor MkBoundedInternal
  boundedValue : Nat

||| Smart constructor
public export
mkBounded : (bound : Nat) -> (value : Nat) -> Maybe (Bounded bound)
mkBounded bound value = if value <= bound
  then Just (MkBoundedInternal value)
  else Nothing

public export
Show (Bounded bound) where
  show b = show (boundedValue b)

public export
Eq (Bounded bound) where
  b1 == b2 = boundedValue b1 == boundedValue b2
