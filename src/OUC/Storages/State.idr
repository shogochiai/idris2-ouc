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
import OUC.Types.Validated
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
keyProposalByStatus : ProposalState -> ProposalId -> String
keyProposalByStatus state pid =
  "proposal" ++ keySep ++ "status" ++ keySep ++ show state ++ keySep ++ padNum 12 pid.value

||| Proposal chain index key
export
keyProposalByChain : ChainId -> ProposalId -> String
keyProposalByChain chain pid =
  "proposal" ++ keySep ++ "chain" ++ keySep ++ padNum 8 chain.value ++ keySep ++ padNum 12 pid.value

||| Auditor primary key
export
keyAuditor : AuditorId -> String
keyAuditor aid = "auditor" ++ keySep ++ principalText aid.principal

||| Auditor status index key
export
keyAuditorByStatus : AuditorStatus -> AuditorId -> String
keyAuditorByStatus status aid =
  "auditor" ++ keySep ++ "status" ++ keySep ++ show status ++ keySep ++ principalText aid.principal

||| Review primary key
export
keyReview : ProposalId -> AuditorId -> String
keyReview pid aid =
  "review" ++ keySep ++ padNum 12 pid.value ++ keySep ++ principalText aid.principal

-- =============================================================================
-- Serialization
-- =============================================================================

||| Field separator for serialized records
fieldSep : String
fieldSep = "|"

||| Serialize ProposalState
serializeState : ProposalState -> String
serializeState SPending     = "0"
serializeState SUnderReview = "1"
serializeState SApproved    = "2"
serializeState SRejected    = "3"
serializeState SExecuted    = "4"
serializeState SExpired     = "5"
serializeState SCancelled   = "6"

||| Deserialize ProposalState
deserializeState : String -> Maybe ProposalState
deserializeState "0" = Just SPending
deserializeState "1" = Just SUnderReview
deserializeState "2" = Just SApproved
deserializeState "3" = Just SRejected
deserializeState "4" = Just SExecuted
deserializeState "5" = Just SExpired
deserializeState "6" = Just SCancelled
deserializeState _   = Nothing

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

||| Serialize Proposal
||| Format: id|chainId|target|newImpl|ou|proposer|rationale|codeHash|status|auditors|created|updated|expires
export
serializeProposal : Proposal -> String
serializeProposal p =
  show p.proposalId ++ fieldSep ++
  show p.chainId ++ fieldSep ++
  evmAddressHex p.target ++ fieldSep ++
  evmAddressHex p.newImpl ++ fieldSep ++
  evmAddressHex p.ou ++ fieldSep ++
  principalText p.proposer ++ fieldSep ++
  p.rationale ++ fieldSep ++
  p.codeHash ++ fieldSep ++
  serializeState p.state ++ fieldSep ++
  show (length p.assignedAuditors) ++ fieldSep ++  -- Auditors stored separately
  show p.createdAt ++ fieldSep ++
  show p.updatedAt ++ fieldSep ++
  show p.expiresAt

||| Serialize Auditor
||| Format: principal|status|reputation|totalReviews|approved|rejected|slashCount|staked|registeredAt
export
serializeAuditor : Auditor -> String
serializeAuditor a =
  principalText a.id.principal ++ fieldSep ++
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
  principalText r.auditorId.principal ++ fieldSep ++
  serializeDecision r.decision ++ fieldSep ++
  r.comment ++ fieldSep ++
  show r.timestamp ++ fieldSep ++
  r.signature

-- =============================================================================
-- Index Queries (prefix patterns for StableBTree scan)
-- =============================================================================

||| Prefix for proposals by status
export
prefixProposalsByStatus : ProposalState -> String
prefixProposalsByStatus state = "proposal" ++ keySep ++ "status" ++ keySep ++ show state ++ keySep

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
