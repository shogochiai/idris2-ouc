||| Auditor Auto-Assignment
|||
||| Integrates risk-based recommendations with auditor selection.
||| Receives recommendation parameters from lazy evm-lifecycle ask
||| and executes appropriate auditor selection from the pool.
|||
||| SPEC: AUDITOR_AUTO_ASSIGN
module AuditorPool.AutoAssign

import FRMonad.Core
import OUC.Core
import AuditorPool.Core
import Data.List
import Data.Nat

%default total

-- =============================================================================
-- Risk Level Types (matches LazyEvmLifecycle.Auditor.Recommend)
-- =============================================================================

||| Risk level for an upgrade (mirrors Lifecycle.Auditor.Recommend.RiskLevel)
public export
data RiskLevel = Critical | High | Medium | Low | None

public export
Eq RiskLevel where
  Critical == Critical = True
  High == High = True
  Medium == Medium = True
  Low == Low = True
  None == None = True
  _ == _ = False

public export
Ord RiskLevel where
  compare Critical Critical = EQ
  compare Critical _ = GT
  compare _ Critical = LT
  compare High High = EQ
  compare High _ = GT
  compare _ High = LT
  compare Medium Medium = EQ
  compare Medium _ = GT
  compare _ Medium = LT
  compare Low Low = EQ
  compare Low _ = GT
  compare _ Low = LT
  compare None None = EQ

public export
Show RiskLevel where
  show Critical = "CRITICAL"
  show High = "HIGH"
  show Medium = "MEDIUM"
  show Low = "LOW"
  show None = "NONE"

-- =============================================================================
-- Assignment Request (input from lazy evm-lifecycle ask)
-- =============================================================================

||| Priority level for auditor assignment
public export
data Priority = Urgent | Normal | Deferred

public export
Eq Priority where
  Urgent == Urgent = True
  Normal == Normal = True
  Deferred == Deferred = True
  _ == _ = False

public export
Show Priority where
  show Urgent = "URGENT"
  show Normal = "NORMAL"
  show Deferred = "DEFERRED"

||| Assignment request from lazy evm-lifecycle ask recommendation
public export
record AssignmentRequest where
  constructor MkAssignmentRequest
  ||| Assessed risk level
  riskLevel : RiskLevel
  ||| Number of auditors to assign
  auditorCount : Nat
  ||| Selection criteria to use
  selectionCriteria : SelectionCriteria
  ||| Minimum reputation threshold (0-1000)
  minReputation : Nat
  ||| Assignment priority
  priority : Priority
  ||| Proposal ID to assign auditors to
  proposalId : Nat

public export
Show AssignmentRequest where
  show r = "AssignmentRequest{"
        ++ "risk=" ++ show r.riskLevel
        ++ ", count=" ++ show r.auditorCount
        ++ ", criteria=" ++ show r.selectionCriteria
        ++ ", minRep=" ++ show r.minReputation
        ++ ", priority=" ++ show r.priority
        ++ ", proposalId=" ++ show r.proposalId
        ++ "}"

-- =============================================================================
-- Assignment Result
-- =============================================================================

||| Result of auto-assignment
public export
record AssignmentResult where
  constructor MkAssignmentResult
  ||| Proposal ID
  proposalId : Nat
  ||| Assigned auditor IDs
  assignedAuditors : List AuditorId
  ||| Actual count assigned (may be less than requested)
  actualCount : Nat
  ||| Warning if fewer auditors than requested
  warning : Maybe String

public export
Show AssignmentResult where
  show r = "AssignmentResult{"
        ++ "proposalId=" ++ show r.proposalId
        ++ ", assigned=" ++ show (length r.assignedAuditors)
        ++ (case r.warning of Nothing => ""; Just w => ", warning=" ++ w)
        ++ "}"

-- =============================================================================
-- Auto-Assignment Functions
-- =============================================================================

||| Create config with custom min reputation
makeConfigWithMinRep : Nat -> PoolConfig
makeConfigWithMinRep minRep =
  { minReputationScore := minRep } defaultConfig

||| Select multiple auditors sequentially
||| Note: Simple implementation, may select same auditor twice if pool is small
selectMultipleAuditors :
  List Auditor ->
  SelectionCriteria ->
  PoolConfig ->
  Nat ->               -- count to select
  Nat ->               -- seed for randomization
  List AuditorId ->    -- accumulator
  FR (List AuditorId)
selectMultipleAuditors auditors criteria config 0 _ acc =
  ok Query "selectMultipleAuditors"
     ("Selected " ++ show (length acc) ++ " auditors")
     (reverse acc)
selectMultipleAuditors auditors criteria config (S k) seed acc = do
  -- Use Random with incrementing seed to vary selection
  let effectiveCriteria = case criteria of
        Random _ => Random seed
        other => other
  result <- selectAuditor auditors effectiveCriteria config
  selectMultipleAuditors auditors criteria config k (seed + 1) (result :: acc)

||| Auto-assign auditors based on recommendation
public export
autoAssignAuditors :
  List Auditor ->
  AssignmentRequest ->
  Nat ->               -- current time (for seed)
  FR AssignmentResult
autoAssignAuditors auditors request now =
  -- No auditors needed for None risk
  if request.riskLevel == None || request.auditorCount == 0
    then ok Update "autoAssignAuditors"
            ("No auditors needed for " ++ show request.riskLevel ++ " risk")
            (MkAssignmentResult request.proposalId [] 0 Nothing)
    else
      let config = makeConfigWithMinRep request.minReputation
          active = getActiveAuditors auditors config
          availableCount = length active
      in if availableCount == 0
        then fail Update "autoAssignAuditors"
                  "No auditors available meeting criteria"
                  (NotFound ("No auditors with reputation >= " ++ show request.minReputation))
        else do
          -- Select up to requested count
          let toSelect = min request.auditorCount availableCount
          selected <- selectMultipleAuditors auditors request.selectionCriteria config toSelect now []
          let warning = if toSelect < request.auditorCount
                then Just ("Requested " ++ show request.auditorCount
                          ++ " but only " ++ show toSelect ++ " available")
                else Nothing
          ok Update "autoAssignAuditors"
             ("Assigned " ++ show (length selected) ++ " auditors to proposal " ++ show request.proposalId)
             (MkAssignmentResult request.proposalId selected (length selected) warning)

-- =============================================================================
-- Quick Assignment (from risk level only)
-- =============================================================================

||| Create assignment request from risk level
||| Uses default parameters based on risk
public export
requestFromRisk : RiskLevel -> Nat -> AssignmentRequest
requestFromRisk risk proposalId =
  case risk of
    Critical => MkAssignmentRequest Critical 5 ByReputation 800 Urgent proposalId
    High     => MkAssignmentRequest High 3 ByReputation 700 Urgent proposalId
    Medium   => MkAssignmentRequest Medium 2 Weighted 500 Normal proposalId
    Low      => MkAssignmentRequest Low 1 ByAvailability 400 Normal proposalId
    None     => MkAssignmentRequest None 0 ByAvailability 0 Deferred proposalId

||| Quick auto-assign from risk level
public export
autoAssignFromRisk :
  List Auditor ->
  RiskLevel ->
  Nat ->               -- proposalId
  Nat ->               -- current time
  FR AssignmentResult
autoAssignFromRisk auditors risk proposalId now =
  autoAssignAuditors auditors (requestFromRisk risk proposalId) now

-- =============================================================================
-- Validation Functions
-- =============================================================================

||| Validate assignment request
public export
validateRequest : AssignmentRequest -> FR ()
validateRequest req =
  if req.minReputation > 1000
    then fail Query "validateRequest"
              ("Invalid minReputation: " ++ show req.minReputation)
              (InvalidState "Reputation must be 0-1000")
    else if req.auditorCount > 10
      then fail Query "validateRequest"
                ("Too many auditors requested: " ++ show req.auditorCount)
                (InvalidState "Maximum 10 auditors per assignment")
      else ok Query "validateRequest" "Request valid" ()

||| Check if enough auditors are available for request
public export
checkAuditorAvailability :
  List Auditor ->
  AssignmentRequest ->
  FR Nat               -- Returns available count
checkAuditorAvailability auditors request =
  let config = makeConfigWithMinRep request.minReputation
      active = getActiveAuditors auditors config
      count = length active
  in if count == 0
    then fail Query "checkAuditorAvailability"
              ("No auditors with reputation >= " ++ show request.minReputation)
              (NotFound "No auditors meeting criteria")
    else ok Query "checkAuditorAvailability"
            (show count ++ " auditors available")
            count
