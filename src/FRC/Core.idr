||| Failure-Recovery Calculus Core Types for ICP
|||
||| This module defines the fundamental FRC types adapted for ICP canister development.
||| Based on the FRC paper: "Failure-Recovery Calculus for World-Computer Virtual Machines"
|||
||| Key principles:
||| - Classify failures instead of hiding them
||| - Force observability (evidence always present)
||| - Localize blast radius (explicit boundaries)
||| - Require recovery procedures
module FRC.Core

%default total

-- =============================================================================
-- Phase: Execution context boundaries for ICP canisters
-- =============================================================================

||| ICP canister lifecycle phases
||| Each phase represents a distinct execution boundary with different capabilities
public export
data Phase
  = Init           -- Canister initialization
  | PreUpgrade     -- Before upgrade (save state)
  | PostUpgrade    -- After upgrade (restore state)
  | Update         -- State-modifying call
  | Query          -- Read-only call
  | Heartbeat      -- Periodic execution
  | Inspect        -- Message inspection
  | Timer          -- Timer callback
  | HttpRequest    -- HTTP outcall context

public export
Show Phase where
  show Init        = "Init"
  show PreUpgrade  = "PreUpgrade"
  show PostUpgrade = "PostUpgrade"
  show Update      = "Update"
  show Query       = "Query"
  show Heartbeat   = "Heartbeat"
  show Inspect     = "Inspect"
  show Timer       = "Timer"
  show HttpRequest = "HttpRequest"

-- =============================================================================
-- Failure Surface: Classified failures for ICP
-- =============================================================================

||| ICP-specific failure classifications
||| These form a closed sum type - no "Unknown" failures allowed
public export
data IcpFail
  = Trap String                         -- ic0.trap equivalent
  | Reject Int String                   -- Canister rejection (code, message)
  | SysInvariant String                 -- System invariant violation
  | DecodeError String                  -- Candid/data decoding failure
  | EncodeError String                  -- Candid/data encoding failure
  | StableMemError String               -- Stable memory operation failure
  | CallError String                    -- Inter-canister call failure
  | Unauthorized String                 -- Permission/auth failure
  | Conflict String                     -- Optimistic concurrency conflict
  | NotFound String                     -- Resource not found
  | InvalidState String                 -- State machine violation
  | RateLimited String                  -- Rate/resource limit exceeded
  | Timeout String                      -- Operation timeout
  | Internal String                     -- Internal error (last resort)

public export
Show IcpFail where
  show (Trap s)          = "Trap: " ++ s
  show (Reject c m)      = "Reject(" ++ show c ++ "): " ++ m
  show (SysInvariant s)  = "SysInvariant: " ++ s
  show (DecodeError s)   = "DecodeError: " ++ s
  show (EncodeError s)   = "EncodeError: " ++ s
  show (StableMemError s)= "StableMemError: " ++ s
  show (CallError s)     = "CallError: " ++ s
  show (Unauthorized s)  = "Unauthorized: " ++ s
  show (Conflict s)      = "Conflict: " ++ s
  show (NotFound s)      = "NotFound: " ++ s
  show (InvalidState s)  = "InvalidState: " ++ s
  show (RateLimited s)   = "RateLimited: " ++ s
  show (Timeout s)       = "Timeout: " ++ s
  show (Internal s)      = "Internal: " ++ s

-- =============================================================================
-- Evidence: Mandatory observability for diagnosis and replay
-- =============================================================================

||| Evidence record - captures context for diagnosis
||| Every FR result must carry evidence regardless of success/failure
public export
record Evidence where
  constructor MkEvidence
  phase     : Phase      -- Execution phase
  label     : String     -- Operation identifier
  detail    : String     -- Additional context
  timestamp : Nat        -- IC time (nanoseconds)
  caller    : String     -- Principal or empty

public export
Show Evidence where
  show e = "[" ++ show e.phase ++ "] " ++ e.label ++ ": " ++ e.detail

||| Empty evidence for pure operations
public export
emptyEvidence : Evidence
emptyEvidence = MkEvidence Query "" "" 0 ""

||| Combine evidence (monoid operation)
public export
combineEvidence : Evidence -> Evidence -> Evidence
combineEvidence e1 e2 = MkEvidence
  e2.phase
  (e1.label ++ " -> " ++ e2.label)
  (e1.detail ++ "; " ++ e2.detail)
  e2.timestamp
  e2.caller

-- =============================================================================
-- FR: The Failure-Recovery Result Type
-- =============================================================================

||| Failure-Recovery result type
||| All computations return either success with evidence or failure with evidence
public export
data FR : Type -> Type where
  Ok   : (value : a) -> (evidence : Evidence) -> FR a
  Fail : (failure : IcpFail) -> (evidence : Evidence) -> FR a

public export
Show a => Show (FR a) where
  show (Ok v e)   = "Ok(" ++ show v ++ ") " ++ show e
  show (Fail f e) = "Fail(" ++ show f ++ ") " ++ show e

||| Check if result is success
public export
isOk : FR a -> Bool
isOk (Ok _ _)   = True
isOk (Fail _ _) = False

||| Check if result is failure
public export
isFail : FR a -> Bool
isFail = not . isOk

||| Extract value or default
public export
fromOk : a -> FR a -> a
fromOk _ (Ok v _)   = v
fromOk d (Fail _ _) = d

||| Extract evidence
public export
getEvidence : FR a -> Evidence
getEvidence (Ok _ e)   = e
getEvidence (Fail _ e) = e

-- =============================================================================
-- Functor, Applicative, Monad instances for FR
-- =============================================================================

public export
Functor FR where
  map f (Ok v e)   = Ok (f v) e
  map f (Fail x e) = Fail x e

public export
Applicative FR where
  pure v = Ok v emptyEvidence
  (Ok f e1) <*> (Ok v e2)   = Ok (f v) (combineEvidence e1 e2)
  (Ok _ e1) <*> (Fail x e2) = Fail x (combineEvidence e1 e2)
  (Fail x e) <*> _          = Fail x e

public export
Monad FR where
  (Ok v e1) >>= f = case f v of
    Ok v' e2   => Ok v' (combineEvidence e1 e2)
    Fail x e2  => Fail x (combineEvidence e1 e2)
  (Fail x e) >>= _ = Fail x e

-- =============================================================================
-- Smart Constructors with Evidence
-- =============================================================================

||| Create success result with evidence
public export
ok : Phase -> String -> String -> a -> FR a
ok phase label detail value = Ok value (MkEvidence phase label detail 0 "")

||| Create failure result with evidence
public export
fail : Phase -> String -> String -> IcpFail -> FR a
fail phase label detail failure = Fail failure (MkEvidence phase label detail 0 "")

||| Create conflict failure (common in optimistic upgrader)
public export
conflict : Phase -> String -> String -> FR a
conflict phase label detail = fail phase label detail (Conflict detail)

||| Create unauthorized failure
public export
unauthorized : Phase -> String -> String -> FR a
unauthorized phase label detail = fail phase label detail (Unauthorized detail)

||| Create not found failure
public export
notFound : Phase -> String -> String -> FR a
notFound phase label detail = fail phase label detail (NotFound detail)

-- =============================================================================
-- Boundary Functions: Recovery closure enforcement
-- =============================================================================

||| Handler type: transforms failures into recovery actions
public export
Handler : Type -> Type -> Type
Handler a b = (IcpFail, Evidence) -> FR b

||| Apply handler to failure, pass through success
public export
handleWith : Handler a a -> FR a -> FR a
handleWith _ (Ok v e)      = Ok v e
handleWith h (Fail f e)    = h (f, e)

||| Boundary function: enforce recovery closure at phase boundary
||| Failures that escape the boundary are converted to trap/reject
public export
boundary : Phase -> FR a -> Either (IcpFail, Evidence) (a, Evidence)
boundary _ (Ok v e)   = Right (v, e)
boundary _ (Fail f e) = Left (f, e)

||| Map FR result, preserving evidence on success
public export
mapOk : (a -> b) -> FR a -> FR b
mapOk f (Ok v e)   = Ok (f v) e
mapOk _ (Fail x e) = Fail x e

||| Catch specific failure type and attempt recovery
public export
catchFail : (IcpFail -> Bool) -> (IcpFail -> Evidence -> FR a) -> FR a -> FR a
catchFail pred recover (Fail f e) = if pred f then recover f e else Fail f e
catchFail _ _ ok = ok
