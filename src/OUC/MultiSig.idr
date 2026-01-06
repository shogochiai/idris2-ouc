||| MultiSig Module
|||
||| Implements n-of-n multisignature voting for upgrade proposals.
||| Both the proposer and all assigned auditors must sign for approval.
module OUC.MultiSig

import FRMonad.Core
import OUC.Core
import Data.List
import Data.Maybe
import Data.String
import Data.Nat

%default total

-- =============================================================================
-- Helper Functions
-- =============================================================================

||| Half of a natural number (n / 2)
half : Nat -> Nat
half Z = Z
half (S Z) = Z
half (S (S n)) = S (half n)

-- =============================================================================
-- Voting Configuration
-- =============================================================================

||| Voting threshold type
public export
data ThresholdType
  = Unanimous          -- n-of-n (all must approve)
  | Majority           -- (n/2)+1 must approve
  | Threshold Nat Nat  -- m-of-n

public export
Show ThresholdType where
  show Unanimous       = "Unanimous"
  show Majority        = "Majority"
  show (Threshold m n) = show m ++ "-of-" ++ show n

||| Voting session for a proposal
public export
record VotingSession where
  constructor MkVotingSession
  proposalId     : ProposalId
  requiredVoters : List AuditorId    -- Assigned auditors
  threshold      : ThresholdType
  votes          : List (AuditorId, ReviewDecision, String)  -- (voter, decision, signature)
  proposerSig    : Maybe String      -- Proposer's signature confirming the proposal
  deadline       : Nat               -- Voting deadline (IC timestamp)
  createdAt      : Nat

public export
Show VotingSession where
  show s = "VotingSession{proposal=" ++ show s.proposalId
        ++ ", voters=" ++ show (length s.requiredVoters)
        ++ ", votes=" ++ show (length s.votes)
        ++ ", threshold=" ++ show s.threshold ++ "}"

-- =============================================================================
-- Voting Logic
-- =============================================================================

||| Check if a decision is an approval
isApprovalDecision : ReviewDecision -> Bool
isApprovalDecision ApproveUpgrade = True
isApprovalDecision _ = False

||| Check if a decision is a rejection
isRejectionDecision : ReviewDecision -> Bool
isRejectionDecision (RejectUpgrade _) = True
isRejectionDecision _ = False

||| Count approvals in votes
countApprovals : List (AuditorId, ReviewDecision, String) -> Nat
countApprovals votes = length $ filter (\(_, d, _) => isApprovalDecision d) votes

||| Count rejections in votes
countRejections : List (AuditorId, ReviewDecision, String) -> Nat
countRejections votes = length $ filter (\(_, d, _) => isRejectionDecision d) votes

||| Check if voting is complete based on threshold
public export
isVotingComplete : VotingSession -> Bool
isVotingComplete session = meetsThreshold session.threshold
  where
    approvals : Nat
    approvals = countApprovals session.votes
    numVoters : Nat
    numVoters = length session.requiredVoters
    hasProposerSig : Bool
    hasProposerSig = isJust session.proposerSig
    meetsThreshold : ThresholdType -> Bool
    meetsThreshold Unanimous = approvals == numVoters && hasProposerSig
    meetsThreshold Majority = approvals > (half numVoters) && hasProposerSig
    meetsThreshold (Threshold m _) = approvals >= m && hasProposerSig

||| Check if voting has failed (cannot reach threshold)
public export
isVotingFailed : VotingSession -> Bool
isVotingFailed session = checkFailed session.threshold
  where
    rejections : Nat
    rejections = countRejections session.votes
    numVoters : Nat
    numVoters = length session.requiredVoters
    checkFailed : ThresholdType -> Bool
    checkFailed Unanimous = rejections > 0  -- Any rejection fails unanimous
    checkFailed Majority = rejections > (half numVoters)
    checkFailed (Threshold m n) = rejections > (n `minus` m)

||| Get final decision from voting session
public export
getFinalDecision : VotingSession -> Maybe ReviewDecision
getFinalDecision session =
  if isVotingFailed session
    then Just (RejectUpgrade "Threshold not achievable")
    else if isVotingComplete session
      then Just ApproveUpgrade
      else Nothing

-- =============================================================================
-- MultiSig Operations (FRC-compliant)
-- =============================================================================

||| Create a new voting session for a proposal
public export
createVotingSession :
  ProposalId ->
  List AuditorId ->
  ThresholdType ->
  Nat ->              -- deadline
  Nat ->              -- currentTime
  FR VotingSession
createVotingSession pid auditors threshold deadline now =
  if null auditors
    then fail Update "createVotingSession" "No auditors assigned"
              (InvalidState "At least one auditor required")
    else if deadline <= now
      then fail Update "createVotingSession" "Invalid deadline"
                (InvalidState "Deadline must be in the future")
      else
        let session = MkVotingSession pid auditors threshold [] Nothing deadline now
        in ok Update "createVotingSession"
              ("Created voting session for " ++ show pid ++ " with " ++ show (length auditors) ++ " auditors")
              session

||| Submit proposer signature to confirm proposal
public export
submitProposerSignature :
  VotingSession ->
  String ->           -- signature
  ICPrincipal ->      -- expected proposer (for validation context)
  FR VotingSession
submitProposerSignature session sig proposer =
  case session.proposerSig of
    Just _ => fail Update "submitProposerSignature" "Already signed"
                   (Conflict "Proposer signature already submitted")
    Nothing =>
      if sig == ""
        then fail Update "submitProposerSignature" "Empty signature"
                  (DecodeError "Signature cannot be empty")
        else
          -- In real implementation, verify signature against proposer's public key
          ok Update "submitProposerSignature"
             ("Proposer signature submitted for " ++ show session.proposalId)
             ({ proposerSig := Just sig } session)

||| Cast vote in voting session
public export
castVote :
  VotingSession ->
  AuditorId ->
  ReviewDecision ->
  String ->           -- signature
  Nat ->              -- currentTime
  FR VotingSession
castVote session aid decision sig now =
  if now > session.deadline
    then fail Update "castVote" "Voting expired"
              (Timeout ("Deadline was " ++ show session.deadline))
    else if not (aid `elem` session.requiredVoters)
      then fail Update "castVote" "Not authorized to vote"
                (Unauthorized (show aid ++ " not in required voters"))
      else if any (\(a, _, _) => a == aid) session.votes
        then fail Update "castVote" "Already voted"
                  (Conflict (show aid ++ " already cast vote"))
        else if null sig
          then fail Update "castVote" "Empty signature"
                    (DecodeError "Vote signature cannot be empty")
          else
            let newVotes = (aid, decision, sig) :: session.votes
            in ok Update "castVote"
                  ("Vote cast by " ++ show aid ++ ": " ++ show decision)
                  ({ votes := newVotes } session)

||| Check voting status
public export
checkVotingStatus :
  VotingSession ->
  Nat ->              -- currentTime
  FR (Either String ReviewDecision)
checkVotingStatus session now =
  if now > session.deadline && not (isVotingComplete session)
    then ok Query "checkVotingStatus" "Voting expired"
            (Left "Voting session expired without reaching threshold")
    else case getFinalDecision session of
      Just decision =>
        ok Query "checkVotingStatus" ("Final decision: " ++ show decision)
           (Right decision)
      Nothing =>
        let voted = length session.votes
            required = length session.requiredVoters
            approvals = countApprovals session.votes
            hasPropSig = isJust session.proposerSig
        in ok Query "checkVotingStatus"
              ("Votes: " ++ show voted ++ "/" ++ show required ++
               ", Approvals: " ++ show approvals ++
               ", ProposerSig: " ++ show hasPropSig)
              (Left "Voting in progress")

-- =============================================================================
-- Signature Aggregation
-- =============================================================================

||| Aggregate signatures for on-chain execution
public export
record AggregatedSignatures where
  constructor MkAggregatedSignatures
  proposalId   : ProposalId
  proposerSig  : String
  auditorSigs  : List (AuditorId, String)
  threshold    : ThresholdType
  totalVoters  : Nat

public export
Show AggregatedSignatures where
  show a = "AggregatedSignatures{proposal=" ++ show a.proposalId
        ++ ", auditors=" ++ show (length a.auditorSigs) ++ "}"

||| Collect all signatures for execution
public export
aggregateSignatures :
  VotingSession ->
  FR AggregatedSignatures
aggregateSignatures session =
  case session.proposerSig of
    Nothing => fail Update "aggregateSignatures" "Missing proposer signature"
                    (InvalidState "Proposer must sign before aggregation")
    Just pSig =>
      if not (isVotingComplete session)
        then fail Update "aggregateSignatures" "Voting not complete"
                  (InvalidState "All required votes not yet cast")
        else
          let approvalSigs = map (\(a, _, s) => (a, s)) $
                             filter (\(_, d, _) => isApprovalDecision d) session.votes
          in ok Update "aggregateSignatures"
                ("Aggregated " ++ show (length approvalSigs) ++ " signatures")
                (MkAggregatedSignatures
                  session.proposalId
                  pSig
                  approvalSigs
                  session.threshold
                  (length session.requiredVoters))

-- =============================================================================
-- Signature Encoding for EVM
-- =============================================================================

||| Encode aggregated signatures for EVM contract call
public export
encodeSignaturesForEvm :
  AggregatedSignatures ->
  FR String
encodeSignaturesForEvm sigs =
  if isNil sigs.auditorSigs
    then fail Update "encodeSignaturesForEvm" "No auditor signatures"
              (InvalidState "At least one auditor signature required")
    else
      -- Format: proposerSig || auditorSig1 || auditorSig2 || ...
      -- Each signature is 65 bytes (r, s, v)
      let allSigs = sigs.proposerSig :: map snd sigs.auditorSigs
          encoded = concat allSigs  -- Simplified; real impl needs proper encoding
      in ok Update "encodeSignaturesForEvm"
            ("Encoded " ++ show (length allSigs) ++ " signatures for EVM")
            encoded

||| Verify signature count matches threshold
public export
verifySignatureCount :
  AggregatedSignatures ->
  FR ()
verifySignatureCount sigs =
  let count = length sigs.auditorSigs
  in case sigs.threshold of
    Unanimous =>
      if count == sigs.totalVoters
        then ok Query "verifySignatureCount" "Unanimous threshold met" ()
        else fail Query "verifySignatureCount"
                  ("Need " ++ show sigs.totalVoters ++ " signatures, have " ++ show count)
                  (InvalidState "Unanimous threshold not met")
    Majority =>
      let required = (half sigs.totalVoters) + 1
      in if count >= required
        then ok Query "verifySignatureCount" "Majority threshold met" ()
        else fail Query "verifySignatureCount"
                  ("Need " ++ show required ++ " signatures, have " ++ show count)
                  (InvalidState "Majority threshold not met")
    Threshold m _ =>
      if count >= m
        then ok Query "verifySignatureCount" "Threshold met" ()
        else fail Query "verifySignatureCount"
                  ("Need " ++ show m ++ " signatures, have " ++ show count)
                  (InvalidState "Threshold not met")
