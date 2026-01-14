||| Batch Polling Optimizer for A-Life Economics
|||
||| Optimizes HTTP outcall batching by:
|||   1. Tier-based priority (RealTime > Standard > Economy > Archive)
|||   2. Cost-aware batch sizing
|||   3. Staggered scheduling to prevent spikes
|||   4. Chain-based grouping for efficiency
|||
||| Key insight: Higher tier protocols pay more, get priority service.
module Economics.BatchOptimizer

import Economics.Tier
import Economics.Types
import Economics.ProtocolAccount
import Economics.Scheduler
import HttpOutcall.CatchUpSync
import MultiChain.Registry
import Data.List
import Data.Nat
import Data.Maybe

%default total

-- =============================================================================
-- Constants
-- =============================================================================

||| Maximum protocols to sync per heartbeat (prevents cycles exhaustion)
public export
maxSyncsPerHeartbeat : Nat
maxSyncsPerHeartbeat = 10

||| Cycles cost per HTTP outcall (from CatchUpSync)
public export
estimatedCyclesPerCall : Nat
estimatedCyclesPerCall = cyclesPerCall  -- 500M cycles

||| Maximum cycles to spend per heartbeat
public export
maxCyclesPerHeartbeat : Nat
maxCyclesPerHeartbeat = 5_000_000_000  -- 5B cycles

-- =============================================================================
-- Priority Calculation
-- =============================================================================

||| Priority score for a protocol account
||| Higher tier = higher priority
||| Also considers time since last sync (staleness)
public export
record SyncPriority where
  constructor MkSyncPriority
  ||| Protocol identifier
  protocolId : EvmAddress
  ||| Chain identifier
  chainId    : ChainId
  ||| Current tier
  tier       : Tier
  ||| Priority score (higher = more urgent)
  score      : Nat
  ||| Time since last sync (seconds)
  staleness  : Nat

public export
Show SyncPriority where
  show p = "Priority{" ++ show p.tier ++ ", score=" ++ show p.score ++ "}"

public export
Eq SyncPriority where
  p1 == p2 = p1.protocolId == p2.protocolId

||| Calculate priority score for an account
||| Formula: tierWeight * 1000 + min(staleness / syncInterval, 100)
||| This ensures tier is primary factor, staleness is secondary
public export
calcPriorityScore : ProtocolAccount -> Nat -> SyncPriority
calcPriorityScore acc now =
  let tierWeight = case acc.currentTier of
                     RealTime => 400
                     Standard => 300
                     Economy  => 200
                     Archive  => 100
      syncInterval = tierSyncInterval acc.currentTier
      staleness = now `minus` acc.lastSyncAt
      -- Staleness bonus: max 100 points
      stalenessBonus = min 100 (staleness `div` max 1 (syncInterval `div` 100))
      score = tierWeight * 1000 + stalenessBonus
  in MkSyncPriority acc.protocolId acc.chainId acc.currentTier score staleness

-- =============================================================================
-- Priority Queue
-- =============================================================================

||| Sort protocols by priority (descending)
public export
sortByPriority : List SyncPriority -> List SyncPriority
sortByPriority = sortBy (\a, b => compare b.score a.score)

||| Get prioritized list of protocols to sync
public export
getPrioritizedSyncs :
  AccountRegistry ->
  Nat ->              -- currentTimestamp
  List SyncPriority
getPrioritizedSyncs reg now =
  let due = getAccountsDueForSync reg now
      priorities = map (\acc => calcPriorityScore acc now) due
  in sortByPriority priorities

-- =============================================================================
-- Batch Planning
-- =============================================================================

||| A planned sync batch
public export
record SyncBatch where
  constructor MkSyncBatch
  ||| Chain to sync
  chainId         : ChainId
  ||| Protocols in this batch
  protocols       : List EvmAddress
  ||| Estimated cycles cost
  estimatedCost   : Nat
  ||| Average tier of protocols
  avgTier         : Tier
  ||| Batch priority (max priority of protocols)
  batchPriority   : Nat

public export
Show SyncBatch where
  show b = "Batch{chain=" ++ show b.chainId.value
        ++ ", count=" ++ show (length b.protocols)
        ++ ", cost=" ++ show b.estimatedCost ++ "}"

||| Estimate HTTP outcall cost for a batch
||| Single eth_call can query multiple balances
public export
estimateBatchCost : List EvmAddress -> Nat
estimateBatchCost protocols =
  -- 1 HTTP call per batch (multicall contract)
  -- Plus overhead per protocol
  let baseCost = estimatedCyclesPerCall
      perProtocolOverhead = 10_000_000  -- 10M per protocol
  in baseCost + (length protocols * perProtocolOverhead)

||| Calculate average tier for a batch
calcAvgTier : List SyncPriority -> Tier
calcAvgTier [] = Archive
calcAvgTier priorities =
  let tierValues = map tierVal priorities
      avgVal = (sum tierValues) `div` (max 1 (length tierValues))
  in valToTier avgVal
  where
    tierVal : SyncPriority -> Nat
    tierVal p = case p.tier of
      RealTime => 4
      Standard => 3
      Economy => 2
      Archive => 1
    sum : List Nat -> Nat
    sum = foldr (+) 0
    valToTier : Nat -> Tier
    valToTier v = if v >= 4 then RealTime
                  else if v >= 3 then Standard
                  else if v >= 2 then Economy
                  else Archive

||| Create optimized sync batches from prioritized list
|||
||| Strategy:
|||   1. Group by chain
|||   2. Sort by highest priority protocol in batch
|||   3. Limit total batches by cycles budget
public export
createOptimizedBatches :
  List SyncPriority ->
  Nat ->              -- maxCycles
  Nat ->              -- maxProtocols
  List SyncBatch
createOptimizedBatches priorities maxCycles maxProtos =
  let -- Take only up to maxProtocols
      limited = take maxProtos priorities
      -- Group by chain
      grouped = groupByChainPriority limited
      -- Create batches
      batches = map mkBatch grouped
      -- Sort batches by priority
      sorted = sortBy (\a, b => compare b.batchPriority a.batchPriority) batches
      -- Filter by budget
  in filterByBudget sorted maxCycles 0 []
  where
    groupByChainPriority : List SyncPriority -> List (ChainId, List SyncPriority)
    groupByChainPriority ps =
      let chainIds = nub (map (.chainId) ps)
          groupOne : ChainId -> (ChainId, List SyncPriority)
          groupOne chain = (chain, filter (\p => p.chainId == chain) ps)
      in map groupOne chainIds

    mkBatch : (ChainId, List SyncPriority) -> SyncBatch
    mkBatch (chain, ps) =
      let addrs = map (.protocolId) ps
          cost = estimateBatchCost addrs
          maxPrio = foldl max 0 (map (.score) ps)
      in MkSyncBatch chain addrs cost (calcAvgTier ps) maxPrio

    filterByBudget : List SyncBatch -> Nat -> Nat -> List SyncBatch -> List SyncBatch
    filterByBudget [] _ _ acc = reverse acc
    filterByBudget (b :: bs) budget spent acc =
      let newSpent = spent + b.estimatedCost
      in if newSpent <= budget
         then filterByBudget bs budget newSpent (b :: acc)
         else reverse acc

-- =============================================================================
-- Staggered Scheduling
-- =============================================================================

||| Stagger window for distributing syncs across time
public export
record StaggerWindow where
  constructor MkStaggerWindow
  ||| Window start timestamp
  windowStart : Nat
  ||| Window duration (seconds)
  duration    : Nat
  ||| Number of slots in window
  slots       : Nat

||| Default stagger window: 1 hour with 12 slots (5 min each)
public export
defaultStaggerWindow : Nat -> StaggerWindow
defaultStaggerWindow now = MkStaggerWindow now 3600 12

||| Calculate which slot a protocol should sync in
||| Uses protocol address hash for deterministic distribution
public export
calcSyncSlot : StaggerWindow -> EvmAddress -> Nat
calcSyncSlot window (MkEvmAddress addr) =
  -- Simple hash: sum of ASCII values mod slots
  let charSum = foldl (\acc, c => acc + cast (ord c)) 0 (unpack addr)
  in charSum `mod` max 1 window.slots

||| Check if a protocol is in the current slot
public export
isInCurrentSlot : StaggerWindow -> Nat -> EvmAddress -> Bool
isInCurrentSlot window currentTs protocolId =
  let elapsed = currentTs `minus` window.windowStart
      currentSlot = elapsed `div` max 1 (window.duration `div` window.slots)
      protocolSlot = calcSyncSlot window protocolId
  in currentSlot == protocolSlot

||| Filter protocols to only those in current time slot
public export
filterBySlot :
  StaggerWindow ->
  Nat ->              -- currentTimestamp
  List SyncPriority ->
  List SyncPriority
filterBySlot window now priorities =
  filter (\p => isInCurrentSlot window now p.protocolId) priorities

-- =============================================================================
-- Optimizer Result
-- =============================================================================

||| Result of batch optimization
public export
record OptimizedSchedule where
  constructor MkOptimizedSchedule
  ||| Batches to execute now
  immediateBatches : List SyncBatch
  ||| Protocols deferred to next slot
  deferredCount    : Nat
  ||| Total estimated cycles
  totalCyclesCost  : Nat
  ||| Total protocols scheduled
  totalProtocols   : Nat

public export
Show OptimizedSchedule where
  show s = "Schedule{batches=" ++ show (length s.immediateBatches)
        ++ ", deferred=" ++ show s.deferredCount
        ++ ", cost=" ++ show s.totalCyclesCost
        ++ ", protocols=" ++ show s.totalProtocols ++ "}"

||| Create optimized schedule for current heartbeat
|||
||| This is the main entry point for batch optimization.
public export
createOptimizedSchedule :
  AccountRegistry ->
  Nat ->              -- currentTimestamp
  Nat ->              -- cyclesBudget
  OptimizedSchedule
createOptimizedSchedule reg now budget =
  let -- Get all due protocols with priority
      allPriorities = getPrioritizedSyncs reg now
      -- Apply stagger window
      window = defaultStaggerWindow now
      inSlot = filterBySlot window now allPriorities
      deferred = length allPriorities `minus` length inSlot
      -- Create optimized batches
      batches = createOptimizedBatches inSlot budget maxSyncsPerHeartbeat
      -- Calculate totals
      totalCost = foldl (\acc, b => acc + b.estimatedCost) 0 batches
      totalProtos = foldl (\acc, b => acc + length b.protocols) 0 batches
  in MkOptimizedSchedule batches deferred totalCost totalProtos

-- =============================================================================
-- Queries
-- =============================================================================

||| Get next batch to execute
public export
getNextBatch : OptimizedSchedule -> Maybe SyncBatch
getNextBatch sched = head' sched.immediateBatches

||| Check if any syncs are scheduled
public export
hasPendingSyncs : OptimizedSchedule -> Bool
hasPendingSyncs sched = not (null sched.immediateBatches)

||| Get all protocols from all batches
public export
getAllScheduledProtocols : OptimizedSchedule -> List EvmAddress
getAllScheduledProtocols sched =
  concatMap (.protocols) sched.immediateBatches

||| Estimate time to complete all batches (seconds)
||| Assumes ~2 seconds per HTTP call
public export
estimateCompletionTime : OptimizedSchedule -> Nat
estimateCompletionTime sched =
  length sched.immediateBatches * 2

