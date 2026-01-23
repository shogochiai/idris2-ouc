||| OptimisticUpgraderCanister Core Types
|||
||| The OUC is the central coordinator for upgrade proposals across EVM chains.
||| It manages:
||| - Upgrade proposal lifecycle
||| - Auditor assignment and selection
||| - Signature authority (vetKeys)
||| - Evidence collection for FRC compliance
module OUC.Functions.Core

import FRMonad.Core
import OUC.Types.Validated
import Data.List

%default total

-- =============================================================================
-- Chain and Address Types
-- =============================================================================

||| EVM Chain identifier
public export
record ChainId where
  constructor MkChainId
  value : Nat

public export
Show ChainId where
  show c = "Chain(" ++ show c.value ++ ")"

public export
Eq ChainId where
  c1 == c2 = c1.value == c2.value

||| EVM Address (20 bytes as hex string for simplicity)
||| DEPRECATED: For new code, use ValidatedEvmAddress from OUC.Types.Validated
||| which provides compile-time format guarantees.
public export
record EvmAddress where
  constructor MkEvmAddress
  hex : String

public export
Show EvmAddress where
  show a = a.hex

public export
Eq EvmAddress where
  a1 == a2 = a1.hex == a2.hex

||| Convert legacy EvmAddress to validated (fails if invalid format)
public export
toValidatedAddress : EvmAddress -> Maybe ValidatedEvmAddress
toValidatedAddress addr = mkEvmAddress addr.hex

||| Convert validated address back to legacy type
public export
fromValidatedAddress : ValidatedEvmAddress -> EvmAddress
fromValidatedAddress va = MkEvmAddress (evmAddressHex va)

||| ICP Principal (as string representation)
||| DEPRECATED: For new code, use ValidatedPrincipal from OUC.Types.Validated
||| which provides compile-time format guarantees.
public export
record ICPrincipal where
  constructor MkICPrincipal
  text : String

public export
Show ICPrincipal where
  show p = p.text

public export
Eq ICPrincipal where
  p1 == p2 = p1.text == p2.text

||| Convert legacy ICPrincipal to validated (fails if invalid format)
public export
toValidatedPrincipal : ICPrincipal -> Maybe ValidatedPrincipal
toValidatedPrincipal p = mkPrincipal p.text

||| Convert validated principal back to legacy type
public export
fromValidatedPrincipal : ValidatedPrincipal -> ICPrincipal
fromValidatedPrincipal vp = MkICPrincipal (principalText vp)

-- =============================================================================
-- Auditor Types (must be before UpgradeProposal which uses AuditorId)
-- =============================================================================

||| Auditor identifier
public export
record AuditorId where
  constructor MkAuditorId
  principal : ValidatedPrincipal

public export
Show AuditorId where
  show a = "Auditor(" ++ show a.principal ++ ")"

public export
Eq AuditorId where
  a1 == a2 = a1.principal == a2.principal

-- =============================================================================
-- Proposal Types
-- =============================================================================

||| Unique proposal identifier
public export
record ProposalId where
  constructor MkProposalId
  value : Nat

public export
Show ProposalId where
  show p = "Proposal#" ++ show p.value

public export
Eq ProposalId where
  p1 == p2 = p1.value == p2.value

-- Note: ProposalStatus is replaced by ProposalState from OUC.Types.Validated
-- Note: UpgradeProposal is replaced by Proposal from OUC.Types.Validated

-- =============================================================================
-- Auditor Status and Record Types
-- =============================================================================

||| Auditor status
public export
data AuditorStatus
  = Active       -- Can receive new assignments
  | Suspended    -- Temporarily unavailable
  | Slashed      -- Penalized, under review
  | Inactive     -- Voluntarily inactive

public export
Show AuditorStatus where
  show Active    = "Active"
  show Suspended = "Suspended"
  show Slashed   = "Slashed"
  show Inactive  = "Inactive"

public export
Eq AuditorStatus where
  Active    == Active    = True
  Suspended == Suspended = True
  Slashed   == Slashed   = True
  Inactive  == Inactive  = True
  _         == _         = False

||| Auditor record
public export
record Auditor where
  constructor MkAuditor
  id             : AuditorId
  status         : AuditorStatus
  reputation     : Nat           -- Reputation score (0-1000)
  totalReviews   : Nat
  approvedCount  : Nat
  rejectedCount  : Nat
  slashCount     : Nat
  stakedAmount   : Nat           -- Staked tokens
  registeredAt   : Nat

public export
Show Auditor where
  show a = "Auditor{" ++ show a.id ++ ", status=" ++ show a.status
        ++ ", reputation=" ++ show a.reputation ++ "}"

-- =============================================================================
-- Review Types
-- =============================================================================

||| Review decision
public export
data ReviewDecision
  = ApproveUpgrade
  | RejectUpgrade String             -- reason
  | RequestChanges String            -- changes

public export
Show ReviewDecision where
  show ApproveUpgrade       = "Approve"
  show (RejectUpgrade r)    = "Reject: " ++ r
  show (RequestChanges c)   = "RequestChanges: " ++ c

||| Review record
public export
record Review where
  constructor MkReview
  proposalId : ProposalId
  auditorId  : AuditorId
  decision   : ReviewDecision
  comment    : String
  timestamp  : Nat
  signature  : String          -- Signature proving auditor identity

public export
Show Review where
  show r = "Review{proposal=" ++ show r.proposalId
        ++ ", auditor=" ++ show r.auditorId
        ++ ", decision=" ++ show r.decision ++ "}"

-- =============================================================================
-- OUC State
-- =============================================================================

||| OUC Canister State
public export
record OUCState where
  constructor MkOUCState
  nextProposalId : Nat
  proposals      : List Proposal
  auditors       : List Auditor
  reviews        : List Review
  owner          : ValidatedPrincipal
  version        : Nat

||| Initial OUC state
public export
initialState : ValidatedPrincipal -> OUCState
initialState owner = MkOUCState 1 [] [] [] owner 1

-- =============================================================================
-- OUC Operations (FRC-compliant)
-- =============================================================================

||| Submit a new upgrade proposal
public export
submitProposal :
  OUCState ->
  ChainId ->
  ValidatedEvmAddress ->  -- target
  ValidatedEvmAddress ->  -- newImpl
  ValidatedEvmAddress ->  -- ou
  ValidatedPrincipal ->   -- proposer
  String ->               -- rationale
  String ->               -- codeHash
  Nat ->                  -- currentTime
  FR (OUCState, ProposalId)
submitProposal state chainId target newImpl ou proposer rationale codeHash now =
  let proposalId = MkProposalId state.nextProposalId
      expiresAt = now + 604800000000000  -- 7 days in nanoseconds
      -- Create pending proposal
      proposal = newProposal state.nextProposalId chainId.value target newImpl ou proposer rationale codeHash now expiresAt
      newState = { nextProposalId := state.nextProposalId + 1
                 , proposals := proposal :: state.proposals
                 } state
  in ok Update "submitProposal" ("Created " ++ show proposalId) (newState, proposalId)

||| Find proposal by ID
public export
findProposal : OUCState -> ProposalId -> FR Proposal
findProposal state pid =
  case findById pid.value state.proposals of
    Just p => ok Query "findProposal" ("Found " ++ show pid) p
    Nothing => notFound Query "findProposal" ("Proposal " ++ show pid ++ " not found")

||| Assign auditor to proposal (only Pending proposals can be assigned)
public export
assignAuditorToProposal :
  OUCState ->
  ProposalId ->
  AuditorId ->
  Nat ->             -- currentTime
  FR OUCState
assignAuditorToProposal state pid aid now =
  case findByIdInState pid.value SPending state.proposals of
    Just pending =>
      case assignAuditor pending aid.principal now of
        Just assigned =>
          -- Update the list: replace old with new
          let updateProposal : Proposal -> Proposal
              updateProposal p = if p.proposalId == pid.value then assigned else p
              newProposals = map updateProposal state.proposals
              newState = MkOUCState state.nextProposalId newProposals state.auditors state.reviews state.owner state.version
          in ok Update "assignAuditor" ("Assigned " ++ show aid ++ " to " ++ show pid) newState
        Nothing =>
          fail Update "assignAuditor" ("Failed to assign auditor to " ++ show pid)
               (InvalidState "Transition failed")
    Nothing =>
      -- Not found OR not in Pending state
      fail Update "assignAuditor" ("Cannot assign to proposal " ++ show pid)
           (InvalidState "Proposal not found or not in Pending status")

||| Submit review for proposal (only UnderReview proposals can be reviewed)
public export
submitReview :
  OUCState ->
  ProposalId ->
  AuditorId ->
  ReviewDecision ->
  String ->          -- comment
  String ->          -- signature
  Nat ->             -- currentTime
  FR OUCState
submitReview state pid aid decision comment sig now =
  case findByIdInState pid.value SUnderReview state.proposals of
    Just underReview =>
      let review = MkReview pid aid decision comment now sig
          -- Transition based on decision
          transitioned : Maybe Proposal
          transitioned = case decision of
            ApproveUpgrade    => approveProposal underReview now
            RejectUpgrade _   => rejectProposal underReview now
            RequestChanges _  => Just underReview  -- stays in review
      in case transitioned of
        Just newProp =>
          let updateProposal : Proposal -> Proposal
              updateProposal p = if p.proposalId == pid.value then newProp else p
              newProposals = map updateProposal state.proposals
              newState = MkOUCState state.nextProposalId newProposals state.auditors (review :: state.reviews) state.owner state.version
          in ok Update "submitReview" ("Review submitted for " ++ show pid) newState
        Nothing =>
          fail Update "submitReview" ("Transition failed for " ++ show pid)
               (InvalidState "State transition failed")
    Nothing =>
      fail Update "submitReview" ("Cannot review proposal " ++ show pid)
           (InvalidState "Proposal not found or not under review")

||| Mark proposal as executed (only Approved proposals can be executed)
public export
markExecuted :
  OUCState ->
  ProposalId ->
  String ->          -- txHash evidence
  Nat ->             -- currentTime
  FR OUCState
markExecuted state pid txHash now =
  case findByIdInState pid.value SApproved state.proposals of
    Just approved =>
      case executeProposal approved now of
        Just executed =>
          let updateProposal : Proposal -> Proposal
              updateProposal p = if p.proposalId == pid.value then executed else p
              newProposals = map updateProposal state.proposals
              newState = MkOUCState state.nextProposalId newProposals state.auditors state.reviews state.owner state.version
          in ok Update "markExecuted" ("Executed " ++ show pid ++ " tx=" ++ txHash) newState
        Nothing =>
          fail Update "markExecuted" ("Transition failed for " ++ show pid)
               (InvalidState "State transition failed")
    Nothing =>
      fail Update "markExecuted" ("Cannot execute proposal " ++ show pid)
           (InvalidState "Proposal not found or not approved")
