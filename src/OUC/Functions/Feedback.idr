||| OUC Feedback Loop
|||
||| Implements the feedback mechanism for rejected proposals.
||| Key principle: OUC rejection = Feedback, not Failure Sink.
|||
||| Features:
||| - Structured rejection reasons (not just strings)
||| - Feedback events for proposer learning
||| - Challenge/Freeze/Resume flow for disputed decisions
||| - Re-proposal tracking with lineage
module OUC.Functions.Feedback

import FRMonad.Core
import OUC.Functions.Core
import Data.List
import Data.Maybe

%default total

-- =============================================================================
-- Rejection Reason Types
-- =============================================================================

||| Category of rejection
public export
data RejectCategory
  = SecurityIssue          -- Security vulnerability found
  | LogicError             -- Logical flaw in implementation
  | InceptionDrift         -- Drifts from Inception intent
  | BoundaryViolation      -- Violates hard constraints
  | InsufficientEvidence   -- Not enough proof/testing
  | CompatibilityIssue     -- Breaks existing functionality
  | GasInefficiency        -- Unacceptable gas costs
  | CodeQuality            -- Code quality/style issues
  | Other String           -- Other reason

public export
Show RejectCategory where
  show SecurityIssue = "SecurityIssue"
  show LogicError = "LogicError"
  show InceptionDrift = "InceptionDrift"
  show BoundaryViolation = "BoundaryViolation"
  show InsufficientEvidence = "InsufficientEvidence"
  show CompatibilityIssue = "CompatibilityIssue"
  show GasInefficiency = "GasInefficiency"
  show CodeQuality = "CodeQuality"
  show (Other s) = "Other(" ++ s ++ ")"

public export
Eq RejectCategory where
  SecurityIssue == SecurityIssue = True
  LogicError == LogicError = True
  InceptionDrift == InceptionDrift = True
  BoundaryViolation == BoundaryViolation = True
  InsufficientEvidence == InsufficientEvidence = True
  CompatibilityIssue == CompatibilityIssue = True
  GasInefficiency == GasInefficiency = True
  CodeQuality == CodeQuality = True
  (Other a) == (Other b) = a == b
  _ == _ = False

||| Severity of rejection
public export
data RejectSeverity
  = Blocking         -- Must be fixed before resubmission
  | Major            -- Significant issue, needs attention
  | Minor            -- Small issue, could be improved
  | Suggestion       -- Optional improvement

public export
Show RejectSeverity where
  show Blocking = "Blocking"
  show Major = "Major"
  show Minor = "Minor"
  show Suggestion = "Suggestion"

public export
Eq RejectSeverity where
  Blocking == Blocking = True
  Major == Major = True
  Minor == Minor = True
  Suggestion == Suggestion = True
  _ == _ = False

||| Structured rejection reason
public export
record RejectReason where
  constructor MkRejectReason
  category    : RejectCategory
  severity    : RejectSeverity
  description : String
  location    : Maybe String    -- File/function location if applicable
  suggestion  : Maybe String    -- How to fix

public export
Show RejectReason where
  show r = "[" ++ show r.severity ++ "] " ++ show r.category ++ ": " ++ r.description

-- =============================================================================
-- Feedback Event Types
-- =============================================================================

||| Feedback event for proposer
public export
record FeedbackEvent where
  constructor MkFeedbackEvent
  proposalId      : ProposalId
  timestamp       : Nat
  auditorId       : AuditorId
  reasons         : List RejectReason
  overallVerdict  : String           -- Summary
  canResubmit     : Bool             -- Whether resubmission is allowed
  resubmitGuidance: Maybe String     -- How to improve for resubmission

public export
Show FeedbackEvent where
  show f = "Feedback{proposal=" ++ show f.proposalId
        ++ ", reasons=" ++ show (length f.reasons)
        ++ ", canResubmit=" ++ show f.canResubmit ++ "}"

||| Check if feedback allows resubmission
export
allowsResubmission : FeedbackEvent -> Bool
allowsResubmission = (.canResubmit)

||| Get blocking issues from feedback
export
getBlockingIssues : FeedbackEvent -> List RejectReason
getBlockingIssues f = filter (\r => r.severity == Blocking) f.reasons

-- =============================================================================
-- Re-proposal Tracking
-- =============================================================================

||| Re-proposal lineage
public export
record ProposalLineage where
  constructor MkProposalLineage
  originalId    : ProposalId
  currentId     : ProposalId
  ancestry      : List ProposalId   -- [original, v2, v3, ..., current]
  version       : Nat
  lastFeedback  : Maybe FeedbackEvent

||| Create initial lineage for new proposal
export
initLineage : ProposalId -> ProposalLineage
initLineage pid = MkProposalLineage pid pid [pid] 1 Nothing

||| Add new version to lineage
export
addVersion : ProposalLineage -> ProposalId -> FeedbackEvent -> ProposalLineage
addVersion lineage newId feedback =
  { currentId := newId
  , ancestry := lineage.ancestry ++ [newId]
  , version := lineage.version + 1
  , lastFeedback := Just feedback
  } lineage

-- =============================================================================
-- Challenge/Freeze/Resume Types
-- =============================================================================

||| Challenge state
public export
data ChallengeState
  = NoChallengeState        -- No active challenge (renamed to avoid conflict)
  | Challenged              -- Challenge raised
  | UnderInvestigation      -- Being investigated
  | ChallengeResolved Bool  -- Resolved: True = challenge upheld, False = rejected

public export
Show ChallengeState where
  show NoChallengeState = "None"
  show Challenged = "Challenged"
  show UnderInvestigation = "UnderInvestigation"
  show (ChallengeResolved b) = "Resolved(" ++ show b ++ ")"

public export
Eq ChallengeState where
  NoChallengeState == NoChallengeState = True
  Challenged == Challenged = True
  UnderInvestigation == UnderInvestigation = True
  (ChallengeResolved a) == (ChallengeResolved b) = a == b
  _ == _ = False

||| Challenge record
public export
record ChallengeRecord where
  constructor MkChallengeRecord
  proposalId     : ProposalId
  challengerId   : ICPrincipal
  reason         : String
  evidence       : List String     -- IPFS hashes or on-chain references
  state          : ChallengeState
  createdAt      : Nat
  resolvedAt     : Maybe Nat

||| Freeze record (when proposal is frozen due to challenge)
public export
record FreezeRecord where
  constructor MkFreezeRecord
  proposalId     : ProposalId
  challenge      : ChallengeRecord
  frozenAt       : Nat
  previousStatus : ProposalStatus
  unfrozenAt     : Maybe Nat

-- =============================================================================
-- Feedback Loop State
-- =============================================================================

||| Complete feedback loop state
public export
record FeedbackState where
  constructor MkFeedbackState
  feedbackEvents : List FeedbackEvent
  lineages       : List ProposalLineage
  challenges     : List ChallengeRecord
  freezes        : List FreezeRecord

||| Initialize empty feedback state
export
initFeedbackState : FeedbackState
initFeedbackState = MkFeedbackState [] [] [] []

-- =============================================================================
-- Feedback Operations
-- =============================================================================

||| Create feedback event from rejection
export
createFeedback :
  ProposalId ->
  AuditorId ->
  List RejectReason ->
  Nat ->
  FeedbackEvent
createFeedback pid aid reasons timestamp =
  let hasBlocking = any (\r => r.severity == Blocking) reasons
      hasBoundary = any (\r => r.category == BoundaryViolation) reasons
      canResub = not hasBoundary  -- Boundary violations cannot be resubmitted
      guidance = if hasBlocking
                   then Just "Address all blocking issues before resubmission"
                   else if null reasons
                     then Nothing
                     else Just "Consider addressing the feedback points"
      verdict = if hasBoundary
                  then "Rejected: Boundary violation - cannot resubmit"
                  else if hasBlocking
                    then "Rejected: Blocking issues found"
                    else "Rejected: Issues found, resubmission possible"
  in MkFeedbackEvent pid timestamp aid reasons verdict canResub guidance

||| Record feedback event
export
recordFeedback :
  FeedbackState ->
  FeedbackEvent ->
  FeedbackState
recordFeedback state event =
  { feedbackEvents := event :: state.feedbackEvents } state

||| Get feedback for proposal
export
getFeedbackFor : FeedbackState -> ProposalId -> List FeedbackEvent
getFeedbackFor state pid =
  filter (\f => f.proposalId == pid) state.feedbackEvents

-- =============================================================================
-- Challenge Operations
-- =============================================================================

||| Raise a challenge against a decision
export
raiseChallenge :
  FeedbackState ->
  ProposalId ->
  ICPrincipal ->
  String ->
  List String ->
  Nat ->
  FR (FeedbackState, ChallengeRecord)
raiseChallenge state pid challenger reason evidence timestamp =
  -- Check if already challenged
  let existing = find (\c => c.proposalId == pid && c.state == Challenged) state.challenges
  in case existing of
    Just _ => fail Update "raiseChallenge" "Already challenged"
                   (Conflict "Proposal already has active challenge")
    Nothing =>
      let challenge = MkChallengeRecord pid challenger reason evidence Challenged timestamp Nothing
          newState = { challenges := challenge :: state.challenges } state
      in ok Update "raiseChallenge"
            ("Challenge raised for " ++ show pid)
            (newState, challenge)

||| Freeze proposal due to challenge
export
freezeProposal :
  FeedbackState ->
  ChallengeRecord ->
  ProposalStatus ->
  Nat ->
  FeedbackState
freezeProposal state challenge prevStatus timestamp =
  let freeze = MkFreezeRecord challenge.proposalId challenge timestamp prevStatus Nothing
  in { freezes := freeze :: state.freezes } state

||| Resolve challenge
export
resolveChallenge :
  FeedbackState ->
  ProposalId ->
  Bool ->           -- True = challenge upheld (original decision wrong)
  Nat ->
  FR FeedbackState
resolveChallenge state pid upheld timestamp =
  case find (\c => c.proposalId == pid) state.challenges of
    Nothing => notFound Update "resolveChallenge" ("No challenge for " ++ show pid)
    Just challenge =>
      let resolved = { state := ChallengeResolved upheld
                     , resolvedAt := Just timestamp
                     } challenge
          updatedChallenges = map (\c => if c.proposalId == pid then resolved else c)
                                  state.challenges
          -- Unfreeze if exists
          setUnfrozen : FreezeRecord -> FreezeRecord
          setUnfrozen f = { unfrozenAt := Just timestamp } f
          updatedFreezes = map (\f => if f.proposalId == pid
                                        then setUnfrozen f
                                        else f)
                               state.freezes
      in ok Update "resolveChallenge"
            ("Challenge resolved for " ++ show pid ++ ": upheld=" ++ show upheld)
            ({ challenges := updatedChallenges
             , freezes := updatedFreezes
             } state)

||| Resume proposal after challenge resolution
export
resumeProposal :
  FeedbackState ->
  ProposalId ->
  FR ProposalStatus
resumeProposal state pid =
  case find (\f => f.proposalId == pid) state.freezes of
    Nothing => notFound Query "resumeProposal" ("No freeze record for " ++ show pid)
    Just freeze =>
      case freeze.unfrozenAt of
        Nothing => fail Query "resumeProposal" "Still frozen"
                        (InvalidState "Challenge not yet resolved")
        Just _ =>
          -- Check if challenge was upheld
          case find (\c => c.proposalId == pid) state.challenges of
            Nothing => ok Query "resumeProposal" "No challenge found" freeze.previousStatus
            Just challenge =>
              case challenge.state of
                ChallengeResolved True =>
                  -- Challenge upheld: reverse the decision
                  ok Query "resumeProposal"
                     "Challenge upheld, reversing decision"
                     (reverseStatus freeze.previousStatus)
                ChallengeResolved False =>
                  -- Challenge rejected: keep original decision
                  ok Query "resumeProposal"
                     "Challenge rejected, keeping decision"
                     freeze.previousStatus
                _ => fail Query "resumeProposal" "Challenge not resolved"
                          (InvalidState "Challenge still pending")
  where
    reverseStatus : ProposalStatus -> ProposalStatus
    reverseStatus Approved = Rejected
    reverseStatus Rejected = Approved
    reverseStatus s = s

-- =============================================================================
-- Lineage Operations
-- =============================================================================

||| Register new proposal in lineage
export
registerProposal :
  FeedbackState ->
  ProposalId ->
  Maybe ProposalId ->   -- Parent proposal (if resubmission)
  FeedbackState
registerProposal state pid parentOpt =
  case parentOpt of
    Nothing =>
      -- New proposal, create fresh lineage
      let lineage = initLineage pid
      in { lineages := lineage :: state.lineages } state
    Just parentId =>
      -- Resubmission, extend existing lineage
      case find (\l => l.currentId == parentId) state.lineages of
        Nothing =>
          -- Parent not found, create new lineage anyway
          let lineage = initLineage pid
          in { lineages := lineage :: state.lineages } state
        Just parentLineage =>
          case getFeedbackFor state parentId of
            [] =>
              -- No feedback, just add version
              let updated = { currentId := pid
                            , ancestry := parentLineage.ancestry ++ [pid]
                            , version := parentLineage.version + 1
                            } parentLineage
                  newLineages = map (\l => if l.originalId == parentLineage.originalId
                                             then updated else l)
                                    state.lineages
              in { lineages := newLineages } state
            (fb :: _) =>
              let updated = addVersion parentLineage pid fb
                  newLineages = map (\l => if l.originalId == parentLineage.originalId
                                             then updated else l)
                                    state.lineages
              in { lineages := newLineages } state

||| Get proposal lineage
export
getLineage : FeedbackState -> ProposalId -> Maybe ProposalLineage
getLineage state pid =
  find (\l => elem pid l.ancestry) state.lineages

||| Get resubmission count
export
getResubmissionCount : FeedbackState -> ProposalId -> Nat
getResubmissionCount state pid =
  case getLineage state pid of
    Nothing => 0
    Just lineage => minus lineage.version 1

-- =============================================================================
-- Query Functions
-- =============================================================================

||| Get all proposals with active challenges
export
getChallengedProposals : FeedbackState -> List ProposalId
getChallengedProposals state =
  map (.proposalId) $
  filter (\c => c.state == Challenged || c.state == UnderInvestigation)
         state.challenges

||| Get all frozen proposals
export
getFrozenProposals : FeedbackState -> List ProposalId
getFrozenProposals state =
  map (.proposalId) $
  filter (\f => isNothing f.unfrozenAt) state.freezes

||| Get proposals that can be resubmitted
export
getResubmittableProposals : FeedbackState -> List ProposalId
getResubmittableProposals state =
  map (.proposalId) $
  filter (.canResubmit) state.feedbackEvents

||| Get feedback statistics
export
getFeedbackStats : FeedbackState -> (Nat, Nat, Nat)  -- (total, resubmittable, challenged)
getFeedbackStats state =
  ( length state.feedbackEvents
  , length (filter (.canResubmit) state.feedbackEvents)
  , length (getChallengedProposals state)
  )
