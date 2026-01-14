||| AuditorPool Vote Module
|||
||| Implements n-of-m threshold voting for upgrade proposals.
||| Auditors authenticate via II/Passkey (Principal verification).
||| When threshold is reached, OUC triggers EVM execution.
module AuditorPool.Vote

import FRMonad.Core
import OUC.Functions.Core
import AuditorPool.Core
import Data.List

%default total

-- =============================================================================
-- Vote Types
-- =============================================================================

||| Individual vote record
public export
record Vote where
  constructor MkVote
  proposalId : ProposalId
  chainId    : ChainId
  ouAddress  : EvmAddress
  auditorId  : AuditorId
  approve    : Bool            -- True = approve, False = reject
  timestamp  : Integer         -- IC timestamp

public export
Show Vote where
  show v = "Vote{proposal=" ++ show v.proposalId
        ++ ", auditor=" ++ show v.auditorId
        ++ ", approve=" ++ show v.approve ++ "}"

public export
Eq Vote where
  v1 == v2 = v1.proposalId == v2.proposalId
          && v1.auditorId == v2.auditorId

||| Vote tally for a proposal
public export
record VoteTally where
  constructor MkVoteTally
  proposalId     : ProposalId
  chainId        : ChainId
  ouAddress      : EvmAddress
  approveCount   : Integer
  rejectCount    : Integer
  requiredCount  : Integer     -- n in n-of-m
  totalAssigned  : Integer     -- m in n-of-m
  votes          : List Vote

public export
Show VoteTally where
  show t = "VoteTally{proposal=" ++ show t.proposalId
        ++ ", approve=" ++ show t.approveCount
        ++ "/" ++ show t.requiredCount
        ++ ", reject=" ++ show t.rejectCount ++ "}"

||| Threshold result
public export
data ThresholdResult
  = NotReached           -- Still collecting votes
  | ApprovalReached      -- n approvals reached
  | RejectionReached     -- m - n + 1 rejections (cannot reach approval)
  | Expired              -- Voting period ended

public export
Show ThresholdResult where
  show NotReached       = "NotReached"
  show ApprovalReached  = "ApprovalReached"
  show RejectionReached = "RejectionReached"
  show Expired          = "Expired"

public export
Eq ThresholdResult where
  NotReached       == NotReached       = True
  ApprovalReached  == ApprovalReached  = True
  RejectionReached == RejectionReached = True
  Expired          == Expired          = True
  _                == _                = False

-- =============================================================================
-- Vote State
-- =============================================================================

||| Voting configuration
public export
record VoteConfig where
  constructor MkVoteConfig
  requiredApprovals : Integer  -- n in n-of-m
  votingPeriod      : Integer  -- Duration in nanoseconds

||| Default voting config: 2-of-3
public export
defaultVoteConfig : VoteConfig
defaultVoteConfig = MkVoteConfig 2 86400000000000  -- 24 hours

||| Vote state per proposal
public export
record ProposalVoteState where
  constructor MkProposalVoteState
  proposalId    : ProposalId
  chainId       : ChainId
  ouAddress     : EvmAddress
  assignedIds   : List AuditorId
  votes         : List Vote
  config        : VoteConfig
  startedAt     : Integer
  result        : Maybe ThresholdResult

public export
Show ProposalVoteState where
  show s = "ProposalVoteState{proposal=" ++ show s.proposalId
        ++ ", votes=" ++ show (length s.votes)
        ++ "/" ++ show (length s.assignedIds) ++ "}"

-- =============================================================================
-- Vote Operations (FRC-compliant)
-- =============================================================================

||| Check if auditor is assigned to proposal
isAssigned : AuditorId -> ProposalVoteState -> Bool
isAssigned aid state = any (\a => a == aid) state.assignedIds

||| Check if auditor already voted
hasVoted : AuditorId -> ProposalVoteState -> Bool
hasVoted aid state = any (\v => v.auditorId == aid) state.votes

||| Count approvals
countApprovals : List Vote -> Integer
countApprovals = cast . length . filter (.approve)

||| Count rejections
countRejections : List Vote -> Integer
countRejections = cast . length . filter (not . (.approve))

||| Check threshold result
public export
checkThreshold : ProposalVoteState -> Integer -> ThresholdResult
checkThreshold state now =
  let approvals = countApprovals state.votes
      rejections = countRejections state.votes
      required = state.config.requiredApprovals
      totalAssigned = cast (length state.assignedIds)
      maxPossibleApprovals = totalAssigned - rejections
      deadline = state.startedAt + state.config.votingPeriod
  in if now > deadline
       then Expired
       else if approvals >= required
         then ApprovalReached
         else if maxPossibleApprovals < required
           then RejectionReached
           else NotReached

||| Submit a vote (called by Auditor via Candid)
||| Principal verification happens at canister entry point
public export
submitVote :
  ProposalVoteState ->
  AuditorId ->        -- Verified from caller Principal
  Bool ->             -- approve
  Integer ->          -- currentTime
  FR ProposalVoteState
submitVote state aid approve now =
  -- Check not already decided
  case state.result of
    Just _ => fail Update "submitVote" "Voting already concluded"
                   (InvalidState "Proposal voting has ended")
    Nothing =>
      -- Check auditor is assigned
      if not (isAssigned aid state)
        then fail Update "submitVote" "Auditor not assigned"
                  (Unauthorized ("Auditor " ++ show aid ++ " not assigned to proposal"))
        else
          -- Check not already voted
          if hasVoted aid state
            then fail Update "submitVote" "Already voted"
                      (Conflict "Auditor already voted on this proposal")
            else
              -- Record vote
              let vote = MkVote state.proposalId state.chainId state.ouAddress aid approve now
                  newVotes = vote :: state.votes
                  newState = { votes := newVotes } state
                  threshold = checkThreshold newState now
                  finalState = case threshold of
                    NotReached => newState
                    other      => { result := Just other } newState
              in ok Update "submitVote"
                    ("Vote recorded: " ++ show aid ++ " -> " ++ show approve)
                    finalState

||| Get vote tally for a proposal
public export
getTally : ProposalVoteState -> VoteTally
getTally state = MkVoteTally
  state.proposalId
  state.chainId
  state.ouAddress
  (countApprovals state.votes)
  (countRejections state.votes)
  state.config.requiredApprovals
  (cast (length state.assignedIds))
  state.votes

||| Initialize vote state for a proposal
public export
initVoteState :
  ProposalId ->
  ChainId ->
  EvmAddress ->       -- OU contract address
  List AuditorId ->   -- Assigned auditors
  VoteConfig ->
  Integer ->          -- currentTime
  ProposalVoteState
initVoteState pid cid ou auditors config now =
  MkProposalVoteState pid cid ou auditors [] config now Nothing

-- =============================================================================
-- Batch Operations
-- =============================================================================

||| Find vote state by proposal ID
public export
findVoteState : List ProposalVoteState -> ProposalId -> Maybe ProposalVoteState
findVoteState states pid = find (\s => s.proposalId == pid) states

||| Update vote state in list
public export
updateVoteState : List ProposalVoteState -> ProposalVoteState -> List ProposalVoteState
updateVoteState states newState =
  map (\s => if s.proposalId == newState.proposalId then newState else s) states

||| Get all proposals ready for execution
public export
getApprovedProposals : List ProposalVoteState -> List ProposalVoteState
getApprovedProposals = filter (\s => s.result == Just ApprovalReached)

||| Get all proposals that failed
public export
getRejectedProposals : List ProposalVoteState -> List ProposalVoteState
getRejectedProposals = filter (\s => s.result == Just RejectionReached
                                  || s.result == Just Expired)
