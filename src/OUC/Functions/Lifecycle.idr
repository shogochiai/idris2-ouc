||| Indexed Monad for Proposal Lifecycle
|||
||| Provides type-level guarantees for proposal state transitions:
||| - Cannot approve without review
||| - Cannot execute without approval
||| - Cannot reject already approved proposals
||| - Terminal states (Executed, Rejected, Cancelled, Expired) prevent further transitions
|||
||| Based on Karma.Indexed pattern for ICP call lifecycle.
module OUC.Functions.Lifecycle

import public FRMonad.Indexed
import public FRMonad.Failure
import public FRMonad.Evidence
import OUC.Functions.Core
import Data.List

%default total

-- =============================================================================
-- Proposal State (Type-level)
-- =============================================================================

||| Type-level proposal states
||| These mirror ProposalStatus but are used for indexed monad tracking
public export
data ProposalState : Type where
  SPending     : ProposalState  -- Awaiting auditor assignment
  SUnderReview : ProposalState  -- Assigned to auditor(s)
  SApproved    : ProposalState  -- Approved, awaiting execution
  SRejected    : ProposalState  -- Rejected by auditor(s)
  SExecuted    : ProposalState  -- Successfully executed on-chain
  SExpired     : ProposalState  -- Timed out
  SCancelled   : ProposalState  -- Cancelled by proposer

public export
Show ProposalState where
  show SPending     = "SPending"
  show SUnderReview = "SUnderReview"
  show SApproved    = "SApproved"
  show SRejected    = "SRejected"
  show SExecuted    = "SExecuted"
  show SExpired     = "SExpired"
  show SCancelled   = "SCancelled"

public export
Eq ProposalState where
  SPending     == SPending     = True
  SUnderReview == SUnderReview = True
  SApproved    == SApproved    = True
  SRejected    == SRejected    = True
  SExecuted    == SExecuted    = True
  SExpired     == SExpired     = True
  SCancelled   == SCancelled   = True
  _            == _            = False

-- =============================================================================
-- PFR: Proposal Failure-Recovery Indexed Monad
-- =============================================================================

||| Indexed monad for proposal lifecycle
||| PFR s t a represents a computation that:
|||   - Starts in proposal state s
|||   - Ends in proposal state t
|||   - Produces a value of type a (or fails with Fail)
|||   - Carries evidence regardless of success/failure
|||
||| Key property: Invalid state transitions are compile-time errors
public export
data PFR : (start : ProposalState) -> (end : ProposalState) -> (result : Type) -> Type where
  ||| Pure value, no state change
  PPure : (value : a) -> (evidence : Evidence) -> PFR s s a

  ||| Failure, no state change
  PFail : (failure : Fail) -> (evidence : Evidence) -> PFR s s a

  ||| Sequential composition with state threading
  PBind : PFR s t a -> (a -> PFR t u b) -> PFR s u b

  -- === State Transitions ===

  ||| Assign auditor (Pending → UnderReview)
  ||| This is the ONLY way to enter UnderReview state
  PAssignAuditor : (auditor : AuditorId) -> Evidence -> PFR SPending SUnderReview ()

  ||| Approve proposal (UnderReview → Approved)
  PApprove : Evidence -> PFR SUnderReview SApproved ()

  ||| Reject proposal (UnderReview → Rejected)
  PReject : (reason : String) -> Evidence -> PFR SUnderReview SRejected ()

  ||| Request changes (UnderReview → UnderReview)
  PRequestChanges : (changes : String) -> Evidence -> PFR SUnderReview SUnderReview ()

  ||| Execute approved proposal (Approved → Executed)
  ||| This is the ONLY way to reach Executed state
  PExecute : (txHash : String) -> Evidence -> PFR SApproved SExecuted ()

  ||| Cancel pending proposal (Pending → Cancelled)
  PCancel : Evidence -> PFR SPending SCancelled ()

  ||| Expire pending proposal (Pending → Expired)
  PExpirePending : Evidence -> PFR SPending SExpired ()

  ||| Expire proposal under review (UnderReview → Expired)
  PExpireReview : Evidence -> PFR SUnderReview SExpired ()

-- =============================================================================
-- Show instance
-- =============================================================================

public export
Show a => Show (PFR s t a) where
  show (PPure v e) = "PPure(" ++ show v ++ ")"
  show (PFail f e) = "PFail(" ++ show f ++ ")"
  show (PBind x f) = "PBind(...)"
  show (PAssignAuditor a e) = "PAssignAuditor(" ++ show a ++ ")"
  show (PApprove e) = "PApprove"
  show (PReject r e) = "PReject(" ++ r ++ ")"
  show (PRequestChanges c e) = "PRequestChanges(" ++ c ++ ")"
  show (PExecute h e) = "PExecute(" ++ h ++ ")"
  show (PCancel e) = "PCancel"
  show (PExpirePending e) = "PExpirePending"
  show (PExpireReview e) = "PExpireReview"

-- =============================================================================
-- Indexed Functor
-- =============================================================================

||| Map over the result, preserving state indices
public export
pmap : (a -> b) -> PFR s t a -> PFR s t b
pmap f (PPure v e) = PPure (f v) e
pmap f (PFail x e) = PFail x e
pmap f (PBind m k) = PBind m (\a => pmap f (k a))
pmap f (PAssignAuditor a e) = PBind (PAssignAuditor a e) (\() => PPure (f ()) e)
pmap f (PApprove e) = PBind (PApprove e) (\() => PPure (f ()) e)
pmap f (PReject r e) = PBind (PReject r e) (\() => PPure (f ()) e)
pmap f (PRequestChanges c e) = PBind (PRequestChanges c e) (\() => PPure (f ()) e)
pmap f (PExecute h e) = PBind (PExecute h e) (\() => PPure (f ()) e)
pmap f (PCancel e) = PBind (PCancel e) (\() => PPure (f ()) e)
pmap f (PExpirePending e) = PBind (PExpirePending e) (\() => PPure (f ()) e)
pmap f (PExpireReview e) = PBind (PExpireReview e) (\() => PPure (f ()) e)

-- =============================================================================
-- Indexed Monad Operations
-- =============================================================================

||| Pure value injection (no state change)
public export
ppure : a -> PFR s s a
ppure v = PPure v emptyEvidence

||| Pure with evidence
public export
ppureWith : a -> Evidence -> PFR s s a
ppureWith = PPure

||| Failure (no state change)
public export
pfail : Fail -> PFR s s a
pfail f = PFail f emptyEvidence

||| Failure with evidence
public export
pfailWith : Fail -> Evidence -> PFR s s a
pfailWith = PFail

||| Sequential composition (bind)
public export
pbind : PFR s t a -> (a -> PFR t u b) -> PFR s u b
pbind = PBind

||| Sequential composition, discarding first result
public export
pthen : PFR s t () -> PFR t u b -> PFR s u b
pthen m1 m2 = PBind m1 (\() => m2)

-- =============================================================================
-- State Transition Operations
-- =============================================================================

||| Assign auditor to proposal (Pending → UnderReview)
public export
passignAuditor : AuditorId -> PFR SPending SUnderReview ()
passignAuditor aid = PAssignAuditor aid
  (mkEvidence Update "passignAuditor" ("Assigned auditor " ++ show aid))

||| Assign auditor with evidence
public export
passignAuditorWith : AuditorId -> Evidence -> PFR SPending SUnderReview ()
passignAuditorWith = PAssignAuditor

||| Approve proposal (UnderReview → Approved)
public export
papprove : PFR SUnderReview SApproved ()
papprove = PApprove (mkEvidence Update "papprove" "Proposal approved")

||| Approve with evidence
public export
papproveWith : Evidence -> PFR SUnderReview SApproved ()
papproveWith = PApprove

||| Reject proposal (UnderReview → Rejected)
public export
preject : String -> PFR SUnderReview SRejected ()
preject reason = PReject reason
  (mkEvidence Update "preject" ("Rejected: " ++ reason))

||| Reject with evidence
public export
prejectWith : String -> Evidence -> PFR SUnderReview SRejected ()
prejectWith = PReject

||| Request changes (UnderReview → UnderReview)
public export
prequestChanges : String -> PFR SUnderReview SUnderReview ()
prequestChanges changes = PRequestChanges changes
  (mkEvidence Update "prequestChanges" ("Requested: " ++ changes))

||| Request changes with evidence
public export
prequestChangesWith : String -> Evidence -> PFR SUnderReview SUnderReview ()
prequestChangesWith = PRequestChanges

||| Execute approved proposal (Approved → Executed)
public export
pexecute : String -> PFR SApproved SExecuted ()
pexecute txHash = PExecute txHash
  (mkEvidence Update "pexecute" ("Executed: " ++ txHash))

||| Execute with evidence
public export
pexecuteWith : String -> Evidence -> PFR SApproved SExecuted ()
pexecuteWith = PExecute

||| Cancel pending proposal (Pending → Cancelled)
public export
pcancel : PFR SPending SCancelled ()
pcancel = PCancel (mkEvidence Update "pcancel" "Proposal cancelled")

||| Cancel with evidence
public export
pcancelWith : Evidence -> PFR SPending SCancelled ()
pcancelWith = PCancel

||| Expire pending proposal (Pending → Expired)
public export
pexpirePending : PFR SPending SExpired ()
pexpirePending = PExpirePending (mkEvidence Update "pexpire" "Pending proposal expired")

||| Expire proposal under review (UnderReview → Expired)
public export
pexpireReview : PFR SUnderReview SExpired ()
pexpireReview = PExpireReview (mkEvidence Update "pexpire" "Review proposal expired")

-- =============================================================================
-- Computation within a state (no state change)
-- =============================================================================

||| Perform a pure computation, staying in the same state
public export
pcompute : a -> PFR s s a
pcompute = ppure

||| Guard that fails if condition is false (no state change)
public export
pguard : Bool -> Fail -> PFR s s ()
pguard True  _ = ppure ()
pguard False f = pfail f

||| Require Maybe to be Just (no state change)
public export
prequireJust : Maybe a -> Fail -> PFR s s a
prequireJust (Just v) _ = ppure v
prequireJust Nothing  f = pfail f

||| Require Either to be Right (no state change)
public export
prequireRight : Either String a -> (String -> Fail) -> PFR s s a
prequireRight (Right v) _ = ppure v
prequireRight (Left e) f  = pfail (f e)

-- =============================================================================
-- Evidence manipulation
-- =============================================================================

||| Add tag to evidence in PFR
public export
ptag : String -> PFR s t a -> PFR s t a
ptag t (PPure v e) = PPure v (addTag t e)
ptag t (PFail f e) = PFail f (addTag t e)
ptag t (PBind m k) = PBind m (\a => ptag t (k a))
ptag t (PAssignAuditor a e) = PAssignAuditor a (addTag t e)
ptag t (PApprove e) = PApprove (addTag t e)
ptag t (PReject r e) = PReject r (addTag t e)
ptag t (PRequestChanges c e) = PRequestChanges c (addTag t e)
ptag t (PExecute h e) = PExecute h (addTag t e)
ptag t (PCancel e) = PCancel (addTag t e)
ptag t (PExpirePending e) = PExpirePending (addTag t e)
ptag t (PExpireReview e) = PExpireReview (addTag t e)

-- =============================================================================
-- Do-notation support
-- =============================================================================

||| Namespace for indexed do-notation
namespace PFR
  public export
  (>>=) : PFR s t a -> (a -> PFR t u b) -> PFR s u b
  (>>=) = PBind

  public export
  (>>) : PFR s t () -> PFR t u b -> PFR s u b
  (>>) = pthen

  public export
  pure : a -> PFR s s a
  pure = ppure

-- =============================================================================
-- Result type for running PFR
-- =============================================================================

||| Result of running a PFR computation
public export
data PFRResult : ProposalState -> Type -> Type where
  ||| Successful completion with value
  PROk : (value : a) -> (evidence : Evidence) -> (finalState : ProposalState) -> PFRResult s a
  ||| Failed with error
  PRFail : (failure : Fail) -> (evidence : Evidence) -> (finalState : ProposalState) -> PFRResult s a

public export
Show a => Show (PFRResult s a) where
  show (PROk v e s) = "PROk(" ++ show v ++ ", " ++ show s ++ ")"
  show (PRFail f e s) = "PRFail(" ++ show f ++ ", " ++ show s ++ ")"

-- =============================================================================
-- Type-level proofs (documentation)
-- =============================================================================

-- Proof: Cannot approve without review
-- papprove : PFR SUnderReview SApproved ()
-- This requires starting in SUnderReview state.
-- There's no way to reach SApproved from SPending directly.

-- Proof: Cannot execute without approval
-- pexecute : PFR SApproved SExecuted ()
-- This requires SApproved state, which requires papprove first.

-- Proof: Cannot reject after approval
-- preject : PFR SUnderReview SRejected ()
-- This requires SUnderReview, but after papprove we're in SApproved.
-- Type mismatch prevents composition.

-- Proof: Cannot modify terminal states
-- SExecuted, SRejected, SCancelled, SExpired are terminal.
-- No PFR constructors produce transitions FROM these states.

-- =============================================================================
-- Example type signatures
-- =============================================================================

-- Full lifecycle: Pending → Executed
-- fullApprovalFlow : AuditorId -> String -> PFR SPending SExecuted ()
-- fullApprovalFlow aid txHash = PFR.do
--   passignAuditor aid    -- Pending → UnderReview
--   papprove              -- UnderReview → Approved
--   pexecute txHash       -- Approved → Executed

-- Rejection flow: Pending → Rejected
-- rejectionFlow : AuditorId -> String -> PFR SPending SRejected ()
-- rejectionFlow aid reason = PFR.do
--   passignAuditor aid    -- Pending → UnderReview
--   preject reason        -- UnderReview → Rejected

-- Cancellation: Pending → Cancelled
-- cancelFlow : PFR SPending SCancelled ()
-- cancelFlow = pcancel   -- Pending → Cancelled

-- COMPILE ERROR: Cannot approve pending proposal
-- invalid : PFR SPending SApproved ()
-- invalid = papprove  -- Type error: expected SUnderReview, got SPending

-- COMPILE ERROR: Cannot execute rejected proposal
-- invalid2 : PFR SRejected SExecuted ()
-- invalid2 = pexecute "0x..."  -- Type error: expected SApproved, got SRejected
