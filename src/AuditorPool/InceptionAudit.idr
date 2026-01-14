||| Inception Alignment Audit (Layer 3)
|||
||| Auditor verification that proposals align with Inception intent.
||| Implements drift detection by comparing proposals against:
||| - IntentKeywords (expected vocabulary)
||| - NonGoals (forbidden actions)
||| - Boundary (hard constraints)
|||
||| This is Layer 3 of the 3-layer Auditor responsibility:
||| - Layer 1: Hash verification (Reproducible Build)
||| - Layer 2: Code audit (Security, Logic, Type Safety)
||| - Layer 3: Inception alignment (Intent Audit) <- THIS MODULE
module AuditorPool.InceptionAudit

import FRMonad.Core
import OUC.Functions.Core
import Data.List
import Data.String

%default total

-- =============================================================================
-- Inception Types (Compatible with idris2-subcontract/Inception)
-- =============================================================================

||| Intent keywords that guide LLM proposal generation
public export
record IntentKeywords where
  constructor MkIntentKeywords
  keywords : List String

||| Things the protocol explicitly will NOT do
public export
record NonGoals where
  constructor MkNonGoals
  excluded : List String

||| Hard boundaries that must never be crossed
public export
record Boundary where
  constructor MkBoundary
  constraints : List String

||| Change kinds for auto-adopt policy
public export
data ChangeKind
  = Bugfix
  | GasOptimization
  | Documentation
  | SecurityPatch
  | FeatureAddition
  | FeatureRemoval
  | ParameterChange
  | ArchitecturalChange

public export
Show ChangeKind where
  show Bugfix = "bugfix"
  show GasOptimization = "gas-optimization"
  show Documentation = "documentation"
  show SecurityPatch = "security-patch"
  show FeatureAddition = "feature-addition"
  show FeatureRemoval = "feature-removal"
  show ParameterChange = "parameter-change"
  show ArchitecturalChange = "architectural-change"

public export
Eq ChangeKind where
  Bugfix == Bugfix = True
  GasOptimization == GasOptimization = True
  Documentation == Documentation = True
  SecurityPatch == SecurityPatch = True
  FeatureAddition == FeatureAddition = True
  FeatureRemoval == FeatureRemoval = True
  ParameterChange == ParameterChange = True
  ArchitecturalChange == ArchitecturalChange = True
  _ == _ = False

||| Allowed change kinds for auto-adoption
public export
record AllowedChangeKinds where
  constructor MkAllowedChangeKinds
  allowed : List ChangeKind

||| The complete Inception specification
public export
record InceptionSpec where
  constructor MkInceptionSpec
  intentKeywords     : IntentKeywords
  nonGoals           : NonGoals
  boundary           : Boundary
  allowedChangeKinds : AllowedChangeKinds
  version            : Nat
  ipfsHash           : String

-- =============================================================================
-- Drift Detection Types
-- =============================================================================

||| Drift severity levels
public export
data DriftSeverity
  = None           -- No drift detected
  | Minor          -- Acceptable deviation
  | Moderate       -- Needs review
  | Major          -- Significant deviation
  | Critical       -- Boundary violation

public export
Show DriftSeverity where
  show None = "None"
  show Minor = "Minor"
  show Moderate = "Moderate"
  show Major = "Major"
  show Critical = "Critical"

public export
Eq DriftSeverity where
  None == None = True
  Minor == Minor = True
  Moderate == Moderate = True
  Major == Major = True
  Critical == Critical = True
  _ == _ = False

public export
Ord DriftSeverity where
  compare None None = EQ
  compare None _ = LT
  compare Minor None = GT
  compare Minor Minor = EQ
  compare Minor _ = LT
  compare Moderate None = GT
  compare Moderate Minor = GT
  compare Moderate Moderate = EQ
  compare Moderate _ = LT
  compare Major Critical = LT
  compare Major Major = EQ
  compare Major _ = GT
  compare Critical Critical = EQ
  compare Critical _ = GT

||| Detailed drift finding
public export
record DriftFinding where
  constructor MkDriftFinding
  category    : String       -- "keyword", "nongoal", "boundary"
  severity    : DriftSeverity
  description : String
  evidence    : String       -- Specific text that triggered detection

||| Drift analysis result
public export
record DriftAnalysis where
  constructor MkDriftAnalysis
  findings      : List DriftFinding
  overallScore  : Nat        -- 0-100, higher = more aligned
  maxSeverity   : DriftSeverity
  recommendation: String

-- =============================================================================
-- Auditor Verdict Types
-- =============================================================================

||| Auditor verdict on proposal-Inception alignment
public export
data AuditorVerdict
  = Match                      -- Proposal aligns with Inception
  | DriftDetected DriftAnalysis -- Proposal drifts from intent
  | InsufficientEvidence       -- Cannot determine alignment
  | BoundaryViolation String   -- Hard constraint violated

public export
Show AuditorVerdict where
  show Match = "Match"
  show (DriftDetected a) = "DriftDetected(score=" ++ show a.overallScore ++ ")"
  show InsufficientEvidence = "InsufficientEvidence"
  show (BoundaryViolation r) = "BoundaryViolation(" ++ r ++ ")"

||| Escalation decision
public export
data EscalationDecision
  = NoEscalation              -- Auto-adopt allowed
  | HumanReview String        -- Needs human auditor review
  | Reject String             -- Should be rejected

public export
Show EscalationDecision where
  show NoEscalation = "NoEscalation"
  show (HumanReview r) = "HumanReview(" ++ r ++ ")"
  show (Reject r) = "Reject(" ++ r ++ ")"

-- =============================================================================
-- Proposal Content (for audit)
-- =============================================================================

||| Proposal content to audit
public export
record ProposalContent where
  constructor MkProposalContent
  title       : String
  description : String
  changeKind  : ChangeKind
  diffSummary : String       -- Summary of code changes
  ipfsHash    : String       -- Full proposal on IPFS

-- =============================================================================
-- Drift Detection Functions
-- =============================================================================

||| Check if text contains any of the keywords (case-insensitive)
export
containsKeyword : String -> List String -> Bool
containsKeyword text keywords =
  let lowerText = toLower text
  in any (\kw => isInfixOf (toLower kw) lowerText) keywords

||| Count keyword matches
export
countKeywordMatches : String -> List String -> Nat
countKeywordMatches text keywords =
  let lowerText = toLower text
  in length $ filter (\kw => isInfixOf (toLower kw) lowerText) keywords

||| Check for NonGoal violations
export
detectNonGoalViolation : String -> NonGoals -> Maybe DriftFinding
detectNonGoalViolation text nonGoals =
  let lowerText = toLower text
      violations = filter (\ng => isInfixOf (toLower ng) lowerText) nonGoals.excluded
  in case violations of
       [] => Nothing
       (v :: _) => Just $ MkDriftFinding
         "nongoal"
         Major
         ("Proposal mentions excluded goal: " ++ v)
         v

||| Check for Boundary violations
export
detectBoundaryViolation : String -> Boundary -> Maybe DriftFinding
detectBoundaryViolation text boundary =
  let lowerText = toLower text
      violations = filter (\b => isInfixOf (toLower b) lowerText) boundary.constraints
  in case violations of
       [] => Nothing
       (v :: _) => Just $ MkDriftFinding
         "boundary"
         Critical
         ("Proposal violates boundary constraint: " ++ v)
         v

||| Calculate keyword alignment score
export
keywordAlignmentScore : String -> IntentKeywords -> Nat
keywordAlignmentScore text keywords =
  let matches = countKeywordMatches text keywords.keywords
      total = length keywords.keywords
  in if total == 0 then 100
     else min 100 (divNatNZ (matches * 100) (S (minus total 1)) ItIsSucc)

-- =============================================================================
-- Core Audit Functions
-- =============================================================================

||| Perform drift analysis on proposal content
export
analyzeDrift : InceptionSpec -> ProposalContent -> DriftAnalysis
analyzeDrift spec proposal =
  let fullText = proposal.title ++ " " ++ proposal.description ++ " " ++ proposal.diffSummary

      -- Check NonGoals
      nonGoalFinding = detectNonGoalViolation fullText spec.nonGoals

      -- Check Boundaries
      boundaryFinding = detectBoundaryViolation fullText spec.boundary

      -- Calculate keyword alignment
      kwScore = keywordAlignmentScore fullText spec.intentKeywords

      -- Collect all findings
      findings = catMaybes [nonGoalFinding, boundaryFinding]

      -- Determine max severity
      maxSev = foldr max None (map (.severity) findings)

      -- Calculate overall score (penalize for findings)
      penalizedScore = case maxSev of
        None => kwScore
        Minor => min kwScore 80
        Moderate => min kwScore 60
        Major => min kwScore 40
        Critical => 0

      -- Generate recommendation
      rec = case maxSev of
        None => if kwScore >= 70
                  then "Proposal aligns well with Inception"
                  else "Low keyword alignment, consider review"
        Minor => "Minor drift detected, proceed with caution"
        Moderate => "Moderate drift, human review recommended"
        Major => "Major drift from intent, escalate for review"
        Critical => "Critical: Boundary violation, reject proposal"

  in MkDriftAnalysis findings penalizedScore maxSev rec

||| Audit proposal against Inception
|||
||| @spec     Current Inception specification
||| @proposal Proposal content to audit
export
auditAgainstInception :
  InceptionSpec ->
  ProposalContent ->
  FR AuditorVerdict
auditAgainstInception spec proposal =
  let analysis = analyzeDrift spec proposal
  in case analysis.maxSeverity of
       Critical =>
         case analysis.findings of
           [] => ok Query "auditAgainstInception" "Critical but no findings" (BoundaryViolation "Unknown")
           (f :: _) => ok Query "auditAgainstInception"
                          ("Boundary violation: " ++ f.description)
                          (BoundaryViolation f.evidence)
       None =>
         if analysis.overallScore >= 70
           then ok Query "auditAgainstInception"
                   ("Match: score=" ++ show analysis.overallScore)
                   Match
           else ok Query "auditAgainstInception"
                   ("Low alignment: score=" ++ show analysis.overallScore)
                   (DriftDetected analysis)
       _ =>
         ok Query "auditAgainstInception"
            ("Drift detected: " ++ analysis.recommendation)
            (DriftDetected analysis)

||| Calculate drift score (0-100, higher = more aligned)
export
calculateDriftScore : InceptionSpec -> ProposalContent -> Nat
calculateDriftScore spec proposal =
  let analysis = analyzeDrift spec proposal
  in analysis.overallScore

-- =============================================================================
-- Escalation Logic
-- =============================================================================

||| Check if change kind is auto-adoptable
export
isAutoAdoptable : InceptionSpec -> ChangeKind -> Bool
isAutoAdoptable spec kind = elem kind spec.allowedChangeKinds.allowed

||| Determine if proposal should be escalated
export
shouldEscalate : InceptionSpec -> ProposalContent -> AuditorVerdict -> EscalationDecision
shouldEscalate spec proposal verdict =
  case verdict of
    BoundaryViolation reason =>
      Reject reason
    InsufficientEvidence =>
      HumanReview "Cannot determine alignment, needs human review"
    DriftDetected analysis =>
      case analysis.maxSeverity of
        Critical => Reject analysis.recommendation
        Major => HumanReview ("Major drift: " ++ analysis.recommendation)
        Moderate => HumanReview ("Moderate drift: " ++ analysis.recommendation)
        Minor =>
          if isAutoAdoptable spec proposal.changeKind
            then NoEscalation
            else HumanReview "Minor drift on non-auto-adoptable change"
        None => NoEscalation
    Match =>
      if isAutoAdoptable spec proposal.changeKind
        then NoEscalation
        else HumanReview "Change kind requires human review"

-- =============================================================================
-- Batch Audit
-- =============================================================================

||| Audit result for a single proposal
public export
record AuditResult where
  constructor MkAuditResult
  proposalId : Nat
  verdict    : AuditorVerdict
  escalation : EscalationDecision

||| Batch audit multiple proposals
export
batchAudit :
  InceptionSpec ->
  List (Nat, ProposalContent) ->
  FR (List AuditResult)
batchAudit spec proposals =
  let results = map auditOne proposals
  in ok Query "batchAudit"
        ("Audited " ++ show (length proposals) ++ " proposals")
        results
  where
    auditOne : (Nat, ProposalContent) -> AuditResult
    auditOne (pid, content) =
      let analysis = analyzeDrift spec content
          verdict = case analysis.maxSeverity of
            Critical => BoundaryViolation analysis.recommendation
            None => if analysis.overallScore >= 70 then Match else DriftDetected analysis
            _ => DriftDetected analysis
          esc = shouldEscalate spec content verdict
      in MkAuditResult pid verdict esc

-- =============================================================================
-- Query Functions
-- =============================================================================

||| Get proposals needing human review
export
proposalsNeedingReview : List AuditResult -> List Nat
proposalsNeedingReview results =
  map (.proposalId) $ filter needsReview results
  where
    needsReview : AuditResult -> Bool
    needsReview r = case r.escalation of
      HumanReview _ => True
      _ => False

||| Get proposals to reject
export
proposalsToReject : List AuditResult -> List (Nat, String)
proposalsToReject results =
  mapMaybe getReject results
  where
    getReject : AuditResult -> Maybe (Nat, String)
    getReject r = case r.escalation of
      Reject reason => Just (r.proposalId, reason)
      _ => Nothing

||| Get auto-adoptable proposals
export
proposalsAutoAdoptable : List AuditResult -> List Nat
proposalsAutoAdoptable results =
  map (.proposalId) $ filter isAuto results
  where
    isAuto : AuditResult -> Bool
    isAuto r = case r.escalation of
      NoEscalation => True
      _ => False
