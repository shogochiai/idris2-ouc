||| OUC State Storage Layer
|||
||| Persistent storage for OUC state using StableBTree.
||| Implements the key schema for proposals, auditors, and reviews.
|||
||| Key Schema:
|||   meta:nextProposalId     -> Nat
|||   meta:owner              -> ICPrincipal
|||   meta:version            -> Nat
|||   proposal:{id}           -> UpgradeProposal
|||   proposal:status:{s}:{id}-> ProposalId (index)
|||   auditor:{principal}     -> Auditor
|||   review:{pid}:{aid}      -> Review
module OUC.Storages.State

import OUC.Functions.Core
-- import ICP.StableBTree  -- TODO: fix pack dependency resolution
import Data.List
import Data.String

%default total

-- =============================================================================
-- Key Generation
-- =============================================================================

||| Key separator
keySep : String
keySep = ":"

||| Pad number for lexicographic ordering
padNum : Nat -> Nat -> String
padNum width n =
  let s = show n
      padding = pack (replicate (minus width (length s)) '0')
  in padding ++ s

||| Meta keys
export
keyNextProposalId : String
keyNextProposalId = "meta" ++ keySep ++ "nextProposalId"

export
keyOwner : String
keyOwner = "meta" ++ keySep ++ "owner"

export
keyVersion : String
keyVersion = "meta" ++ keySep ++ "version"

||| Proposal primary key
export
keyProposal : ProposalId -> String
keyProposal pid = "proposal" ++ keySep ++ padNum 12 pid.value

||| Proposal status index key
export
keyProposalByStatus : ProposalStatus -> ProposalId -> String
keyProposalByStatus status pid =
  "proposal" ++ keySep ++ "status" ++ keySep ++ show status ++ keySep ++ padNum 12 pid.value

||| Proposal chain index key
export
keyProposalByChain : ChainId -> ProposalId -> String
keyProposalByChain chain pid =
  "proposal" ++ keySep ++ "chain" ++ keySep ++ padNum 8 chain.value ++ keySep ++ padNum 12 pid.value

||| Auditor primary key
export
keyAuditor : AuditorId -> String
keyAuditor aid = "auditor" ++ keySep ++ aid.principal.text

||| Auditor status index key
export
keyAuditorByStatus : AuditorStatus -> AuditorId -> String
keyAuditorByStatus status aid =
  "auditor" ++ keySep ++ "status" ++ keySep ++ show status ++ keySep ++ aid.principal.text

||| Review primary key
export
keyReview : ProposalId -> AuditorId -> String
keyReview pid aid =
  "review" ++ keySep ++ padNum 12 pid.value ++ keySep ++ aid.principal.text

-- =============================================================================
-- Serialization
-- =============================================================================

||| Field separator for serialized records
fieldSep : String
fieldSep = "|"

||| Serialize ProposalStatus
serializeStatus : ProposalStatus -> String
serializeStatus Pending     = "0"
serializeStatus UnderReview = "1"
serializeStatus Approved    = "2"
serializeStatus Rejected    = "3"
serializeStatus Executed    = "4"
serializeStatus Expired     = "5"
serializeStatus Cancelled   = "6"

||| Deserialize ProposalStatus
deserializeStatus : String -> Maybe ProposalStatus
deserializeStatus "0" = Just Pending
deserializeStatus "1" = Just UnderReview
deserializeStatus "2" = Just Approved
deserializeStatus "3" = Just Rejected
deserializeStatus "4" = Just Executed
deserializeStatus "5" = Just Expired
deserializeStatus "6" = Just Cancelled
deserializeStatus _   = Nothing

||| Serialize AuditorStatus
serializeAuditorStatus : AuditorStatus -> String
serializeAuditorStatus Active    = "0"
serializeAuditorStatus Suspended = "1"
serializeAuditorStatus Slashed   = "2"
serializeAuditorStatus Inactive  = "3"

||| Deserialize AuditorStatus
deserializeAuditorStatus : String -> Maybe AuditorStatus
deserializeAuditorStatus "0" = Just Active
deserializeAuditorStatus "1" = Just Suspended
deserializeAuditorStatus "2" = Just Slashed
deserializeAuditorStatus "3" = Just Inactive
deserializeAuditorStatus _   = Nothing

||| Serialize UpgradeProposal
||| Format: id|chainId|target|newImpl|ou|proposer|rationale|codeHash|status|auditors|created|updated|expires
export
serializeProposal : UpgradeProposal -> String
serializeProposal p =
  show p.id.value ++ fieldSep ++
  show p.chainId.value ++ fieldSep ++
  p.target.hex ++ fieldSep ++
  p.newImpl.hex ++ fieldSep ++
  p.ou.hex ++ fieldSep ++
  p.proposer.text ++ fieldSep ++
  p.rationale ++ fieldSep ++
  p.codeHash ++ fieldSep ++
  serializeStatus p.status ++ fieldSep ++
  show (length p.assignedAuditors) ++ fieldSep ++  -- Auditors stored separately
  show p.createdAt ++ fieldSep ++
  show p.updatedAt ++ fieldSep ++
  show p.expiresAt

||| Serialize Auditor
||| Format: principal|status|reputation|totalReviews|approved|rejected|slashCount|staked|registeredAt
export
serializeAuditor : Auditor -> String
serializeAuditor a =
  a.id.principal.text ++ fieldSep ++
  serializeAuditorStatus a.status ++ fieldSep ++
  show a.reputation ++ fieldSep ++
  show a.totalReviews ++ fieldSep ++
  show a.approvedCount ++ fieldSep ++
  show a.rejectedCount ++ fieldSep ++
  show a.slashCount ++ fieldSep ++
  show a.stakedAmount ++ fieldSep ++
  show a.registeredAt

||| Serialize ReviewDecision
serializeDecision : ReviewDecision -> String
serializeDecision ApproveUpgrade       = "A"
serializeDecision (RejectUpgrade r)    = "R:" ++ r
serializeDecision (RequestChanges c)   = "C:" ++ c

||| Serialize Review
||| Format: proposalId|auditorId|decision|comment|timestamp|signature
export
serializeReview : Review -> String
serializeReview r =
  show r.proposalId.value ++ fieldSep ++
  r.auditorId.principal.text ++ fieldSep ++
  serializeDecision r.decision ++ fieldSep ++
  r.comment ++ fieldSep ++
  show r.timestamp ++ fieldSep ++
  r.signature

-- =============================================================================
-- Index Queries (prefix patterns for StableBTree scan)
-- =============================================================================

||| Prefix for proposals by status
export
prefixProposalsByStatus : ProposalStatus -> String
prefixProposalsByStatus status = "proposal" ++ keySep ++ "status" ++ keySep ++ show status ++ keySep

||| Prefix for proposals by chain
export
prefixProposalsByChain : ChainId -> String
prefixProposalsByChain chain = "proposal" ++ keySep ++ "chain" ++ keySep ++ padNum 8 chain.value ++ keySep

||| Prefix for auditors by status
export
prefixAuditorsByStatus : AuditorStatus -> String
prefixAuditorsByStatus status = "auditor" ++ keySep ++ "status" ++ keySep ++ show status ++ keySep

-- =============================================================================
-- Storage Operations (IO) - Requires ICP.StableBTree
-- =============================================================================
-- TODO: Implement when pack dependency resolution is fixed
-- See: storeProposal, storeAuditor, storeReview, loadProposal*, migrateToStableBTree
