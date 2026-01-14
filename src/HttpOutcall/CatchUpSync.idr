||| Catch-up Sync Module for A-Life Economics
|||
||| When a protocol upgrades from Archive tier or recovers from SUSPENDED,
||| it needs to catch up on missed blocks. This module calculates costs
||| and orchestrates the catch-up sync process.
|||
||| Cost formula (from docs/ecosystem.md ECON-004):
|||   blocksToSync = monthsArchived * 30 * 24 * 60 * 5  (5 blocks/min on Ethereum)
|||   callsNeeded  = blocksToSync / 1000               (batch 1000 blocks per call)
|||   cyclesCost   = callsNeeded * 500_000_000         (500M cycles per HTTP outcall)
|||
||| Example: 6 months archived -> ~22B cycles
module HttpOutcall.CatchUpSync

import Data.Nat
import Economics.Tier
import Economics.Types

%default total

-- =============================================================================
-- Constants
-- =============================================================================

||| Blocks per minute on Ethereum mainnet (average ~12 sec block time)
public export
blocksPerMinute : Nat
blocksPerMinute = 5

||| Minutes per day
public export
minutesPerDay : Nat
minutesPerDay = 24 * 60  -- 1440

||| Days per month (average)
public export
daysPerMonth : Nat
daysPerMonth = 30

||| Blocks we can fetch per HTTP outcall (batching)
public export
blocksPerCall : Nat
blocksPerCall = 1000

||| Cycles cost per HTTP outcall (approximate)
public export
cyclesPerCall : Nat
cyclesPerCall = 500_000_000  -- 500M cycles

-- =============================================================================
-- Cost Calculation
-- =============================================================================

||| Calculate blocks to sync for a given number of months archived
public export
calcBlocksToSync : Nat -> Nat
calcBlocksToSync monthsArchived =
  monthsArchived * daysPerMonth * minutesPerDay * blocksPerMinute

||| Calculate HTTP calls needed for a given block count
||| Uses ceiling division for exact calculation
public export
calcCallsNeeded : Nat -> Nat
calcCallsNeeded blocks = ceilDiv blocks blocksPerCallNZ

||| Calculate total cycles cost for catch-up sync
public export
calcCatchUpCost : Nat -> Nat
calcCatchUpCost monthsArchived =
  let blocks = calcBlocksToSync monthsArchived
      calls = calcCallsNeeded blocks
  in calls * cyclesPerCall

||| Calculate catch-up cost from block range
public export
calcCostFromBlockRange : Nat -> Nat -> Nat
calcCostFromBlockRange fromBlock toBlock =
  if toBlock <= fromBlock
  then 0
  else let blocks = toBlock `minus` fromBlock
           calls = calcCallsNeeded blocks
       in calls * cyclesPerCall

-- =============================================================================
-- Catch-up Request State Machine
-- =============================================================================

||| Status of a catch-up sync operation
public export
data CatchUpStatus
  = CatchUpPending     -- Not yet started
  | CatchUpInProgress  -- Batches being processed
  | CatchUpCompleted   -- All blocks synced
  | CatchUpFailed      -- Error during sync

public export
Show CatchUpStatus where
  show CatchUpPending = "PENDING"
  show CatchUpInProgress = "IN_PROGRESS"
  show CatchUpCompleted = "COMPLETED"
  show CatchUpFailed = "FAILED"

public export
Eq CatchUpStatus where
  CatchUpPending == CatchUpPending = True
  CatchUpInProgress == CatchUpInProgress = True
  CatchUpCompleted == CatchUpCompleted = True
  CatchUpFailed == CatchUpFailed = True
  _ == _ = False

||| A catch-up sync request
public export
record CatchUpRequest where
  constructor MkCatchUpRequest
  ||| Starting block number
  fromBlock      : Nat
  ||| Target block number
  toBlock        : Nat
  ||| Current progress (next block to sync)
  currentBlock   : Nat
  ||| Total estimated cycles cost
  estimatedCost  : Nat
  ||| Cycles spent so far
  cyclesSpent    : Nat
  ||| Number of batches completed
  batchesCompleted : Nat
  ||| Status
  status         : CatchUpStatus
  ||| Timestamp when started
  startedAt      : Nat
  ||| Last updated timestamp
  updatedAt      : Nat

public export
Show CatchUpRequest where
  show req = "CatchUp{" ++ show req.currentBlock ++ "/" ++ show req.toBlock
          ++ ", status=" ++ show req.status
          ++ ", batches=" ++ show req.batchesCompleted ++ "}"

-- =============================================================================
-- Request Lifecycle
-- =============================================================================

||| Create a new catch-up request
public export
createCatchUpRequest : Nat -> Nat -> Nat -> CatchUpRequest
createCatchUpRequest fromBlock toBlock now =
  let cost = calcCostFromBlockRange fromBlock toBlock
  in MkCatchUpRequest
       fromBlock
       toBlock
       fromBlock
       cost
       0
       0
       CatchUpPending
       now
       now

||| Start the catch-up sync (transition to InProgress)
public export
startCatchUp : CatchUpRequest -> Nat -> CatchUpRequest
startCatchUp req now =
  case req.status of
    CatchUpPending => { status := CatchUpInProgress, updatedAt := now } req
    _ => req

||| Process a batch of blocks
||| Returns updated request after processing `blocksProcessed` blocks
public export
processBatch : CatchUpRequest -> Nat -> Nat -> Nat -> CatchUpRequest
processBatch req blocksProcessed cyclesUsed now =
  case req.status of
    CatchUpInProgress =>
      let newCurrent = req.currentBlock + blocksProcessed
          newSpent = req.cyclesSpent + cyclesUsed
          newBatches = req.batchesCompleted + 1
          newStatus = if newCurrent >= req.toBlock
                      then CatchUpCompleted
                      else CatchUpInProgress
      in MkCatchUpRequest
           req.fromBlock
           req.toBlock
           newCurrent
           req.estimatedCost
           newSpent
           newBatches
           newStatus
           req.startedAt
           now
    _ => req  -- No change if not in progress

||| Mark catch-up as failed
public export
failCatchUp : CatchUpRequest -> Nat -> CatchUpRequest
failCatchUp req now =
  case req.status of
    CatchUpInProgress => { status := CatchUpFailed, updatedAt := now } req
    CatchUpPending => { status := CatchUpFailed, updatedAt := now } req
    _ => req

-- =============================================================================
-- Progress Calculation
-- =============================================================================

||| Calculate sync progress percentage (0-100)
public export
syncProgress : CatchUpRequest -> Nat
syncProgress req =
  let totalBlocks = req.toBlock `minus` req.fromBlock
      doneBlocks = req.currentBlock `minus` req.fromBlock
  in pctValue (calcPercentage doneBlocks totalBlocks)

||| Blocks remaining to sync
public export
blocksRemaining : CatchUpRequest -> Nat
blocksRemaining req =
  if req.currentBlock >= req.toBlock
  then 0
  else req.toBlock `minus` req.currentBlock

||| Estimated batches remaining
public export
batchesRemaining : CatchUpRequest -> Nat
batchesRemaining req =
  calcCallsNeeded (blocksRemaining req)

||| Check if catch-up is complete
public export
isCatchUpComplete : CatchUpRequest -> Bool
isCatchUpComplete req = req.status == CatchUpCompleted

-- =============================================================================
-- Cost Estimation Helpers
-- =============================================================================

||| Estimate cost for tier upgrade catch-up
||| Given months at Archive tier, estimate catch-up cost to target tier
public export
estimateUpgradeCost : Nat -> Tier -> Nat
estimateUpgradeCost monthsAtArchive targetTier =
  -- Base catch-up cost for syncing missed blocks
  calcCatchUpCost monthsAtArchive

||| Estimate time to complete catch-up (in minutes)
||| Assumes ~2 seconds per HTTP outcall
public export
estimateCatchUpTime : Nat -> Nat
estimateCatchUpTime monthsArchived =
  let blocks = calcBlocksToSync monthsArchived
      calls = calcCallsNeeded blocks
  in (calls * 2) `div` 60  -- 2 seconds per call, convert to minutes

-- =============================================================================
-- Validation
-- =============================================================================

||| Validate that a catch-up request has valid parameters
public export
validateRequest : CatchUpRequest -> Bool
validateRequest req =
  req.fromBlock <= req.toBlock &&
  req.currentBlock >= req.fromBlock &&
  req.currentBlock <= req.toBlock + 1  -- Can be at toBlock+1 when completed
