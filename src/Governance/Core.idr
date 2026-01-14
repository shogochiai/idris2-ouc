||| Governance-by-Observation Core Types
|||
||| Self-Amending Protocol observability and automatic selection pressure
||| Based on FR Monads failure semantics and Artificial Life principles
module Governance.Core

import Data.List

-- =============================================================================
-- USAGE SIGNAL COLLECTION
-- =============================================================================

||| Time window for aggregated metrics
public export
data TimeWindow
  = Window24h
  | Window7d
  | Window30d
  | WindowAll

export
Show TimeWindow where
  show Window24h = "24h"
  show Window7d = "7d"
  show Window30d = "30d"
  show WindowAll = "all"

||| Usage signals for a protocol
public export
record UsageSignal where
  constructor MkUsageSignal
  protocolId : String
  txCount : Nat
  uniqueCallers : Nat
  totalValueLocked : Nat  -- In smallest unit
  lastActiveAt : Nat      -- Unix timestamp
  window : TimeWindow
  collectedAt : Nat       -- When this signal was collected

||| Protocol adoption metrics
public export
record AdoptionMetrics where
  constructor MkAdoptionMetrics
  protocolId : String
  integratorCount : Nat   -- Contracts calling this protocol
  dependencyDepth : Nat   -- Max downstream hops
  chainCount : Nat        -- Number of chains deployed
  firstDeployedAt : Nat
  measuredAt : Nat

||| Check if protocol is inactive
public export
isInactive : UsageSignal -> Nat -> Nat -> Bool
isInactive signal currentTime dormancyPeriod =
  currentTime > signal.lastActiveAt + dormancyPeriod

-- =============================================================================
-- FAILURE RECORDING (FR Semantics)
-- =============================================================================

||| Failure type from FR taxonomy
public export
data FailureType
  = F_Code String     -- Code logic error
  | F_Audit String    -- Audit-related failure
  | F_Liveness String -- Liveness failure (no response)
  | F_Env String      -- Environment contamination (from FABI)
  | F_Key String      -- Key-related failure
  | F_Unknown String  -- Unclassified failure

export
Show FailureType where
  show (F_Code s) = "f_code: " ++ s
  show (F_Audit s) = "f_audit: " ++ s
  show (F_Liveness s) = "f_liveness: " ++ s
  show (F_Env s) = "f_env: " ++ s
  show (F_Key s) = "f_key: " ++ s
  show (F_Unknown s) = "f_unknown: " ++ s

||| Failure severity levels
public export
data FailureSeverity
  = Critical  -- Fund loss or security breach
  | High      -- Repeated failures
  | Medium    -- Isolated unexpected reverts
  | Low       -- Expected user-error reverts

export
Show FailureSeverity where
  show Critical = "CRITICAL"
  show High = "HIGH"
  show Medium = "MEDIUM"
  show Low = "LOW"

export
Ord FailureSeverity where
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

export
Eq FailureSeverity where
  x == y = compare x y == EQ

||| Individual failure record
public export
record FailureRecord where
  constructor MkFailureRecord
  protocolId : String
  failureType : FailureType
  severity : FailureSeverity
  revertReason : Maybe String
  caller : String
  calldata : String       -- Hex encoded input
  timestamp : Nat
  blockNumber : Nat
  txHash : String

||| Failure statistics for a protocol
public export
record FailureStats where
  constructor MkFailureStats
  protocolId : String
  totalFailures : Nat
  totalSuccesses : Nat
  criticalCount : Nat
  highCount : Nat
  mediumCount : Nat
  lowCount : Nat
  window : TimeWindow
  calculatedAt : Nat

||| Calculate failure rate
public export
failureRate : FailureStats -> Double
failureRate stats =
  let totalCount = cast {to=Double} (stats.totalFailures + stats.totalSuccesses)
  in if totalCount == 0.0
     then 0.0
     else cast {to=Double} stats.totalFailures / totalCount

||| Check if failure rate is trending up
public export
isFailureTrendingUp : FailureStats -> FailureStats -> Bool
isFailureTrendingUp current previous =
  failureRate current > failureRate previous

-- =============================================================================
-- HEALTH STATE MACHINE
-- =============================================================================

||| Protocol health states (matches Health.idr in lazy)
public export
data ProtocolHealth
  = Healthy   -- Active usage + low failure rate
  | Wounded   -- Elevated failure rate
  | Drifting  -- Low usage but functional
  | Frozen    -- Manually quarantined
  | Dead      -- Permanently retired

export
Show ProtocolHealth where
  show Healthy = "HEALTHY"
  show Wounded = "WOUNDED"
  show Drifting = "DRIFTING"
  show Frozen = "FROZEN"
  show Dead = "DEAD"

export
Eq ProtocolHealth where
  Healthy == Healthy = True
  Wounded == Wounded = True
  Drifting == Drifting = True
  Frozen == Frozen = True
  Dead == Dead = True
  _ == _ = False

||| Health assessment result
public export
record HealthAssessment where
  constructor MkHealthAssessment
  protocolId : String
  health : ProtocolHealth
  usageSignal : UsageSignal
  failureStats : FailureStats
  adoptionMetrics : AdoptionMetrics
  assessedAt : Nat
  previousHealth : Maybe ProtocolHealth

-- =============================================================================
-- AUTOMATIC QUARANTINE
-- =============================================================================

||| Quarantine action types
public export
data QuarantineAction
  = Freeze String         -- Freeze with reason
  | RequireAuditors Nat   -- Require more auditors
  | RollbackPending       -- Rollback pending upgrades
  | NoAction              -- No quarantine needed

export
Show QuarantineAction where
  show (Freeze reason) = "FREEZE: " ++ reason
  show (RequireAuditors n) = "REQUIRE_AUDITORS: " ++ show n
  show RollbackPending = "ROLLBACK_PENDING"
  show NoAction = "NO_ACTION"

||| Quarantine event record
public export
record QuarantineEvent where
  constructor MkQuarantineEvent
  protocolId : String
  action : QuarantineAction
  reason : String
  initiator : String      -- "automatic" or auditor/governance ID
  timestamp : Nat
  reversible : Bool

||| Quarantine rule definition
public export
record QuarantineRule where
  constructor MkQuarantineRule
  name : String
  condition : HealthAssessment -> Bool
  action : QuarantineAction

-- =============================================================================
-- RETIREMENT FLOW
-- =============================================================================

||| Retirement proposal
public export
record RetirementProposal where
  constructor MkRetirementProposal
  protocolId : String
  reason : String
  proposedAt : Nat
  frozenSince : Nat
  approvals : List String   -- Governance approvals
  requiredApprovals : Nat

||| Retirement status
public export
data RetirementStatus
  = RetirementPending
  | RetirementApproved
  | RetirementExecuted
  | RetirementRejected String

-- =============================================================================
-- FITNESS SCORE (Selection Pressure)
-- =============================================================================

||| Fitness score components
public export
record FitnessComponents where
  constructor MkFitnessComponents
  usageScore : Double     -- From UsageSignal
  reliabilityScore : Double  -- From FailureStats (inverse)
  adoptionScore : Double  -- From AdoptionMetrics
  recencyScore : Double   -- Time since last activity (decay)

||| Calculated fitness score
public export
record FitnessScore where
  constructor MkFitnessScore
  protocolId : String
  score : Double          -- 0.0 to 100.0
  components : FitnessComponents
  rank : Nat              -- Position in ranking
  percentile : Double     -- Percentile position
  calculatedAt : Nat

||| Fitness history entry
public export
record FitnessHistoryEntry where
  constructor MkFitnessHistoryEntry
  protocolId : String
  score : Double
  timestamp : Nat

-- =============================================================================
-- OBSERVER INFRASTRUCTURE
-- =============================================================================

||| Observer registration
public export
record RegisteredObserver where
  constructor MkRegisteredObserver
  observerId : String
  endpoint : String       -- Callback URL or address
  interestedIn : List String  -- Protocol IDs or "*" for all
  registeredAt : Nat

||| Alert types
public export
data AlertType
  = AlertHealthChange ProtocolHealth ProtocolHealth  -- From, To
  | AlertQuarantine QuarantineEvent
  | AlertFailure FailureRecord
  | AlertRetirement RetirementProposal

export
Show AlertType where
  show (AlertHealthChange from to) = "HEALTH: " ++ show from ++ " -> " ++ show to
  show (AlertQuarantine evt) = "QUARANTINE: " ++ show evt.action
  show (AlertFailure rec) = "FAILURE: " ++ show rec.severity
  show (AlertRetirement prop) = "RETIREMENT: " ++ prop.protocolId

||| Alert record
public export
record Alert where
  constructor MkAlert
  alertId : Nat
  alertType : AlertType
  protocolId : String
  details : String
  createdAt : Nat
  acknowledged : Bool
  acknowledgedBy : Maybe String
  acknowledgedAt : Maybe Nat

-- =============================================================================
-- CONFIGURATION CONSTANTS
-- =============================================================================

||| Dormancy period before protocol considered inactive (seconds)
public export
dormancyPeriod : Nat
dormancyPeriod = 2592000  -- 30 days

||| Failure rate threshold for Healthy state
public export
healthyThreshold : Double
healthyThreshold = 0.01  -- 1%

||| Failure rate threshold for Critical (triggering quarantine)
public export
criticalThreshold : Double
criticalThreshold = 0.1  -- 10%

||| Number of high-severity failures before quarantine
public export
quarantineThreshold : Nat
quarantineThreshold = 5

||| Period before frozen protocol is considered for retirement (seconds)
public export
retirementConsiderationPeriod : Nat
retirementConsiderationPeriod = 7776000  -- 90 days

||| Alert latency requirement for critical alerts (seconds)
public export
alertLatency : Nat
alertLatency = 60  -- 1 minute

||| Period before alert escalation (seconds)
public export
escalationPeriod : Nat
escalationPeriod = 3600  -- 1 hour

||| Window for alert deduplication (seconds)
public export
deduplicationWindow : Nat
deduplicationWindow = 300  -- 5 minutes

-- =============================================================================
-- ASSESSMENT FUNCTIONS
-- =============================================================================

||| Assess protocol health from signals
public export
assessHealth : UsageSignal -> FailureStats -> Nat -> ProtocolHealth
assessHealth usage stats currentTime =
  let rate = failureRate stats
      inactive = isInactive usage currentTime dormancyPeriod
  in if rate >= criticalThreshold
     then Wounded  -- High failure rate (Frozen requires manual action)
     else if inactive && rate < criticalThreshold
          then Drifting
          else if rate < healthyThreshold
               then Healthy
               else Wounded

||| Determine if quarantine is needed
public export
shouldQuarantine : HealthAssessment -> Maybe QuarantineAction
shouldQuarantine assessment =
  let stats = assessment.failureStats
      rate = failureRate stats
  in if stats.criticalCount > 0
     then Just (Freeze "Critical failure detected")
     else if rate >= criticalThreshold
          then Just (Freeze "Failure rate exceeds critical threshold")
          else if stats.highCount >= quarantineThreshold
               then Just (RequireAuditors 2)
               else Nothing

||| Calculate fitness score
public export
calculateFitness : UsageSignal -> FailureStats -> AdoptionMetrics -> Nat -> Double
calculateFitness usage stats adoption currentTime =
  let usageScore = min 30.0 (cast {to=Double} usage.txCount / 1000.0 * 30.0)
      reliability = 1.0 - failureRate stats
      reliabilityScore = reliability * 40.0
      adoptionScore = min 20.0 (cast {to=Double} adoption.integratorCount * 2.0)
      daysSinceActive = cast {to=Double} (currentTime `minus` usage.lastActiveAt) / 86400.0
      recencyScore = max 0.0 (10.0 - daysSinceActive / 3.0)
  in usageScore + reliabilityScore + adoptionScore + recencyScore

||| Check if protocol is in bottom percentile
public export
isBottomPercentile : FitnessScore -> Double -> Bool
isBottomPercentile score threshold =
  score.percentile < threshold
