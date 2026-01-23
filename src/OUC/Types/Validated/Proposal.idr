||| Proposal Types and State Machine
module OUC.Types.Validated.Proposal

import Data.List
import Data.Nat
import OUC.Types.Validated.Address

%default total

-- =============================================================================
-- Proposal State (Runtime validation instead of type-level)
-- =============================================================================

||| Proposal states
public export
data ProposalState = SPending | SUnderReview | SApproved | SRejected | SExecuted | SExpired | SCancelled

public export
Show ProposalState where
  show SPending = "Pending"
  show SUnderReview = "UnderReview"
  show SApproved = "Approved"
  show SRejected = "Rejected"
  show SExecuted = "Executed"
  show SExpired = "Expired"
  show SCancelled = "Cancelled"

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

||| Validate state transition at runtime
public export
isValidTransition : ProposalState -> ProposalState -> Bool
isValidTransition SPending SUnderReview = True
isValidTransition SUnderReview SApproved = True
isValidTransition SUnderReview SRejected = True
isValidTransition SApproved SExecuted = True
isValidTransition SPending SExpired = True
isValidTransition SUnderReview SExpired = True
isValidTransition SPending SCancelled = True
isValidTransition _ _ = False

-- =============================================================================
-- Proposal Record
-- =============================================================================

||| Proposal record with runtime state field
public export
record Proposal where
  constructor MkProposal
  proposalId       : Nat
  chainId          : Nat
  state            : ProposalState
  target           : ValidatedEvmAddress
  newImpl          : ValidatedEvmAddress
  ou               : ValidatedEvmAddress
  proposer         : ValidatedPrincipal
  rationale        : String
  codeHash         : String
  assignedAuditors : List ValidatedPrincipal
  createdAt        : Nat
  updatedAt        : Nat
  expiresAt        : Nat

public export
Show Proposal where
  show p = "Proposal#" ++ show p.proposalId ++ "[" ++ show p.state ++ "]"

public export
Eq Proposal where
  p1 == p2 = p1.proposalId == p2.proposalId

-- =============================================================================
-- Proposal State Transitions
-- =============================================================================

||| Transition proposal to new state (with runtime validation)
public export
transitionTo : ProposalState -> Proposal -> Nat -> Maybe Proposal
transitionTo newState proposal now =
  if isValidTransition proposal.state newState
     then Just ({ state := newState, updatedAt := now } proposal)
     else Nothing

||| Create new proposal (always starts as Pending)
public export
newProposal : Nat -> Nat -> ValidatedEvmAddress -> ValidatedEvmAddress ->
              ValidatedEvmAddress -> ValidatedPrincipal -> String -> String ->
              Nat -> Nat -> Proposal
newProposal pid cid target newImpl ou proposer rationale codeHash now expires =
  MkProposal pid cid SPending target newImpl ou proposer rationale codeHash [] now now expires

||| Assign auditor (Pending -> UnderReview)
public export
assignAuditor : Proposal -> ValidatedPrincipal -> Nat -> Maybe Proposal
assignAuditor proposal auditor now =
  if proposal.state == SPending
     then Just (MkProposal
       proposal.proposalId
       proposal.chainId
       SUnderReview
       proposal.target
       proposal.newImpl
       proposal.ou
       proposal.proposer
       proposal.rationale
       proposal.codeHash
       (auditor :: proposal.assignedAuditors)
       proposal.createdAt
       now
       proposal.expiresAt)
     else Nothing

||| Approve proposal (UnderReview -> Approved)
public export
approveProposal : Proposal -> Nat -> Maybe Proposal
approveProposal p now = transitionTo SApproved p now

||| Reject proposal (UnderReview -> Rejected)
public export
rejectProposal : Proposal -> Nat -> Maybe Proposal
rejectProposal p now = transitionTo SRejected p now

||| Mark as executed (Approved -> Executed)
public export
executeProposal : Proposal -> Nat -> Maybe Proposal
executeProposal p now = transitionTo SExecuted p now

||| Expire proposal (Pending/UnderReview -> Expired)
public export
expireProposal : Proposal -> Nat -> Maybe Proposal
expireProposal p now = transitionTo SExpired p now

||| Cancel proposal (Pending -> Cancelled)
public export
cancelProposal : Proposal -> Nat -> Maybe Proposal
cancelProposal p now = transitionTo SCancelled p now

-- =============================================================================
-- Proposal Filters
-- =============================================================================

||| Filter proposals by state
public export
filterByState : ProposalState -> List Proposal -> List Proposal
filterByState st = filter (\p => p.state == st)

||| Filter pending proposals
public export
filterPending : List Proposal -> List Proposal
filterPending = filterByState SPending

||| Filter under review proposals
public export
filterUnderReview : List Proposal -> List Proposal
filterUnderReview = filterByState SUnderReview

||| Filter approved proposals
public export
filterApproved : List Proposal -> List Proposal
filterApproved = filterByState SApproved

||| Filter rejected proposals
public export
filterRejected : List Proposal -> List Proposal
filterRejected = filterByState SRejected

||| Filter executed proposals
public export
filterExecuted : List Proposal -> List Proposal
filterExecuted = filterByState SExecuted

||| Filter expired proposals
public export
filterExpired : List Proposal -> List Proposal
filterExpired = filterByState SExpired

||| Filter cancelled proposals
public export
filterCancelled : List Proposal -> List Proposal
filterCancelled = filterByState SCancelled

||| Find proposal by ID
public export
findById : Nat -> List Proposal -> Maybe Proposal
findById pid [] = Nothing
findById pid (p :: ps) = if p.proposalId == pid then Just p else findById pid ps

||| Find proposal by ID with expected state
public export
findByIdInState : Nat -> ProposalState -> List Proposal -> Maybe Proposal
findByIdInState pid st ps =
  case findById pid ps of
    Just p => if p.state == st then Just p else Nothing
    Nothing => Nothing
