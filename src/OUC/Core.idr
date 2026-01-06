||| OptimisticUpgraderCanister Core Types
|||
||| The OUC is the central coordinator for upgrade proposals across EVM chains.
||| It manages:
||| - Upgrade proposal lifecycle
||| - Auditor assignment and selection
||| - Signature authority (vetKeys)
||| - Evidence collection for FRC compliance
module OUC.Core

import FRC.Core
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

||| ICP Principal (as string representation)
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

-- =============================================================================
-- Auditor Types (must be before UpgradeProposal which uses AuditorId)
-- =============================================================================

||| Auditor identifier
public export
record AuditorId where
  constructor MkAuditorId
  principal : ICPrincipal

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

||| Proposal status lifecycle
public export
data ProposalStatus
  = Pending        -- Awaiting auditor assignment
  | UnderReview    -- Assigned to auditor(s)
  | Approved       -- Approved, awaiting execution
  | Rejected       -- Rejected by auditor(s)
  | Executed       -- Successfully executed on-chain
  | Expired        -- Timed out
  | Cancelled      -- Cancelled by proposer

public export
Show ProposalStatus where
  show Pending     = "Pending"
  show UnderReview = "UnderReview"
  show Approved    = "Approved"
  show Rejected    = "Rejected"
  show Executed    = "Executed"
  show Expired     = "Expired"
  show Cancelled   = "Cancelled"

public export
Eq ProposalStatus where
  Pending     == Pending     = True
  UnderReview == UnderReview = True
  Approved    == Approved    = True
  Rejected    == Rejected    = True
  Executed    == Executed    = True
  Expired     == Expired     = True
  Cancelled   == Cancelled   = True
  _           == _           = False

||| Upgrade proposal payload
||| Contains all information needed to execute an upgrade
public export
record UpgradeProposal where
  constructor MkUpgradeProposal
  id               : ProposalId
  chainId          : ChainId
  target           : EvmAddress     -- Contract to upgrade (ERC-7546 Proxy)
  newImpl          : EvmAddress     -- New implementation address
  ou               : EvmAddress     -- OptimisticUpgrader contract
  proposer         : ICPrincipal    -- ICP principal who submitted
  rationale        : String         -- Human-readable justification
  codeHash         : String         -- Hash of new implementation code
  status           : ProposalStatus
  assignedAuditors : List AuditorId -- VRF/commit-reveal selected auditors
  createdAt        : Nat            -- IC timestamp (nanoseconds)
  updatedAt        : Nat
  expiresAt        : Nat

public export
Show UpgradeProposal where
  show p = "UpgradeProposal{id=" ++ show p.id ++ ", chain=" ++ show p.chainId
        ++ ", target=" ++ show p.target ++ ", status=" ++ show p.status ++ "}"

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
  proposals      : List UpgradeProposal
  auditors       : List Auditor
  reviews        : List Review
  owner          : ICPrincipal
  version        : Nat

||| Initial OUC state
public export
initialState : ICPrincipal -> OUCState
initialState owner = MkOUCState 1 [] [] [] owner 1

-- =============================================================================
-- OUC Operations (FRC-compliant)
-- =============================================================================

||| Submit a new upgrade proposal
public export
submitProposal :
  OUCState ->
  ChainId ->
  EvmAddress ->      -- target
  EvmAddress ->      -- newImpl
  EvmAddress ->      -- ou
  ICPrincipal ->     -- proposer
  String ->          -- rationale
  String ->          -- codeHash
  Nat ->             -- currentTime
  FR (OUCState, ProposalId)
submitProposal state chainId target newImpl ou proposer rationale codeHash now =
  let proposalId = MkProposalId state.nextProposalId
      expiresAt = now + 604800000000000  -- 7 days in nanoseconds
      proposal = MkUpgradeProposal
        proposalId chainId target newImpl ou proposer rationale codeHash
        Pending [] now now expiresAt  -- assignedAuditors starts empty
      newState = { nextProposalId := state.nextProposalId + 1
                 , proposals := proposal :: state.proposals
                 } state
  in ok Update "submitProposal" ("Created " ++ show proposalId) (newState, proposalId)

||| Find proposal by ID
public export
findProposal : OUCState -> ProposalId -> FR UpgradeProposal
findProposal state pid =
  case find (\p => p.id == pid) state.proposals of
    Just p  => ok Query "findProposal" ("Found " ++ show pid) p
    Nothing => notFound Query "findProposal" ("Proposal " ++ show pid ++ " not found")

||| Assign auditor to proposal
public export
assignAuditor :
  OUCState ->
  ProposalId ->
  AuditorId ->
  Nat ->             -- currentTime
  FR OUCState
assignAuditor state pid aid now = do
  proposal <- findProposal state pid
  case proposal.status of
    Pending =>
      let newAuditors = aid :: proposal.assignedAuditors
          updated : UpgradeProposal
          updated = MkUpgradeProposal
            proposal.id proposal.chainId proposal.target proposal.newImpl
            proposal.ou proposal.proposer proposal.rationale proposal.codeHash
            UnderReview newAuditors proposal.createdAt now proposal.expiresAt
          newProposals = map (\p => if p.id == pid then updated else p) state.proposals
          newState : OUCState
          newState = MkOUCState state.nextProposalId newProposals state.auditors state.reviews state.owner state.version
      in ok Update "assignAuditor" ("Assigned " ++ show aid ++ " to " ++ show pid) newState
    other =>
      fail Update "assignAuditor" ("Cannot assign to " ++ show other ++ " proposal")
           (InvalidState "Proposal not in Pending status")

||| Submit review for proposal
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
submitReview state pid aid decision comment sig now = do
  proposal <- findProposal state pid
  case proposal.status of
    UnderReview =>
      let review = MkReview pid aid decision comment now sig
          newStatus : ProposalStatus
          newStatus = case decision of
            ApproveUpgrade    => Approved
            RejectUpgrade _   => Rejected
            RequestChanges _  => UnderReview
          updated : UpgradeProposal
          updated = MkUpgradeProposal
            proposal.id proposal.chainId proposal.target proposal.newImpl
            proposal.ou proposal.proposer proposal.rationale proposal.codeHash
            newStatus proposal.assignedAuditors proposal.createdAt now proposal.expiresAt
          newProposals = map (\p => if p.id == pid then updated else p) state.proposals
          newState : OUCState
          newState = MkOUCState state.nextProposalId newProposals state.auditors (review :: state.reviews) state.owner state.version
      in ok Update "submitReview" ("Review submitted for " ++ show pid) newState
    other =>
      fail Update "submitReview" ("Cannot review " ++ show other ++ " proposal")
           (InvalidState "Proposal not under review")

||| Mark proposal as executed
public export
markExecuted :
  OUCState ->
  ProposalId ->
  String ->          -- txHash evidence
  Nat ->             -- currentTime
  FR OUCState
markExecuted state pid txHash now = do
  proposal <- findProposal state pid
  case proposal.status of
    Approved =>
      let updated : UpgradeProposal
          updated = MkUpgradeProposal
            proposal.id proposal.chainId proposal.target proposal.newImpl
            proposal.ou proposal.proposer proposal.rationale proposal.codeHash
            Executed proposal.assignedAuditors proposal.createdAt now proposal.expiresAt
          newProposals = map (\p => if p.id == pid then updated else p) state.proposals
          newState : OUCState
          newState = MkOUCState state.nextProposalId newProposals state.auditors state.reviews state.owner state.version
      in ok Update "markExecuted" ("Executed " ++ show pid ++ " tx=" ++ txHash) newState
    other =>
      fail Update "markExecuted" ("Cannot execute " ++ show other ++ " proposal")
           (InvalidState "Proposal not approved")
