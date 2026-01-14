||| Recovery Orchestrator - Integrates Status and CatchUpSync
|||
||| Coordinates the recovery flow when a SUSPENDED account receives a donation:
|||   1. Calculate blocks missed during suspension
|||   2. Estimate catch-up cost
|||   3. Initiate recovery with CatchUpRequest
|||   4. Track progress and complete recovery
|||
||| Flow: SUSPENDED + donation → RECOVERING (with CatchUp) → ACTIVE
module Economics.RecoveryOrchestrator

import Economics.Status
import Economics.Tier
import HttpOutcall.CatchUpSync
import Data.Nat

%default total

-- =============================================================================
-- Recovery Context
-- =============================================================================

||| Full recovery context combining Status and CatchUp state
public export
record RecoveryContext where
  constructor MkRecoveryContext
  ||| Account operational status
  statusCtx      : StatusContext
  ||| Catch-up sync request (if in recovery)
  catchUpReq     : Maybe CatchUpRequest
  ||| Current block on chain (external input)
  currentBlock   : Nat
  ||| Last synced block before suspension
  lastSyncedBlock : Nat

public export
Show RecoveryContext where
  show ctx = "Recovery{status=" ++ show ctx.statusCtx.status
          ++ ", catchUp=" ++ show (map (.status) ctx.catchUpReq)
          ++ ", blocks=" ++ show ctx.lastSyncedBlock ++ "->" ++ show ctx.currentBlock
          ++ "}"

||| Create initial recovery context for a healthy account
public export
initialRecoveryContext : Nat -> Nat -> RecoveryContext
initialRecoveryContext currentBlock lastSynced =
  MkRecoveryContext
    (initialStatusContext 0)
    Nothing
    currentBlock
    lastSynced

-- =============================================================================
-- Recovery Initiation
-- =============================================================================

||| Result of initiating recovery
public export
data RecoveryInitResult
  = RecoveryStarted RecoveryContext Nat  -- context + estimated cost
  | RecoveryNotNeeded RecoveryContext     -- account already active
  | RecoveryNotAllowed String             -- cannot start recovery

public export
Show RecoveryInitResult where
  show (RecoveryStarted ctx cost) = "Started{cost=" ++ show cost ++ "}"
  show (RecoveryNotNeeded ctx) = "NotNeeded"
  show (RecoveryNotAllowed reason) = "NotAllowed{" ++ reason ++ "}"

||| Initiate recovery from SUSPENDED state
||| Takes: context, donation amount, current time
||| Returns: Updated context with CatchUpRequest if successful
public export
initiateRecovery : RecoveryContext -> Nat -> Nat -> RecoveryInitResult
initiateRecovery ctx donationAmount now =
  case ctx.statusCtx.status of
    Active => RecoveryNotNeeded ctx
    Recovering => RecoveryNotAllowed "Already recovering"
    Suspended =>
      let blocksToSync = ctx.currentBlock `minus` ctx.lastSyncedBlock
          catchUpCost = calcCostFromBlockRange ctx.lastSyncedBlock ctx.currentBlock
      in if donationAmount < catchUpCost
         then RecoveryNotAllowed "Insufficient donation for catch-up"
         else
           -- Create catch-up request
           let catchUp = createCatchUpRequest ctx.lastSyncedBlock ctx.currentBlock now
               -- Update status to Recovering
               newStatusCtx = case startRecovery ctx.statusCtx blocksToSync catchUpCost now of
                                Just s => s
                                Nothing => ctx.statusCtx  -- shouldn't happen
               newCtx = { statusCtx := newStatusCtx
                        , catchUpReq := Just catchUp
                        } ctx
           in RecoveryStarted newCtx catchUpCost

-- =============================================================================
-- Recovery Progress
-- =============================================================================

||| Result of processing a recovery batch
public export
data RecoveryProgressResult
  = RecoveryInProgress RecoveryContext Nat  -- context + progress %
  | RecoveryCompleted RecoveryContext
  | RecoveryFailed RecoveryContext String

public export
Show RecoveryProgressResult where
  show (RecoveryInProgress ctx pct) = "InProgress{" ++ show pct ++ "%}"
  show (RecoveryCompleted ctx) = "Completed"
  show (RecoveryFailed ctx reason) = "Failed{" ++ reason ++ "}"

||| Process a batch of blocks during recovery
||| Called after HTTP outcall syncs a batch of blocks
public export
processRecoveryBatch :
  RecoveryContext ->
  Nat ->              -- blocks synced in this batch
  Nat ->              -- cycles used
  Nat ->              -- current time
  RecoveryProgressResult
processRecoveryBatch ctx blocksSynced cyclesUsed now =
  case (ctx.statusCtx.status, ctx.catchUpReq) of
    (Recovering, Just catchUp) =>
      let -- Update catch-up progress
          newCatchUp = processBatch (startCatchUp catchUp now) blocksSynced cyclesUsed now
          progress = syncProgress newCatchUp
          -- Update status recovery progress
          newStatusCtx = updateRecovery ctx.statusCtx blocksSynced cyclesUsed now
          newCtx = { statusCtx := newStatusCtx
                   , catchUpReq := Just newCatchUp
                   , lastSyncedBlock := ctx.lastSyncedBlock + blocksSynced
                   } ctx
      in if isCatchUpComplete newCatchUp
         then -- Catch-up complete, transition to ACTIVE
           let finalStatusCtx = completeRecovery newStatusCtx now
               finalCtx = { statusCtx := finalStatusCtx
                          , catchUpReq := Nothing
                          } newCtx
           in RecoveryCompleted finalCtx
         else RecoveryInProgress newCtx progress
    (Recovering, Nothing) =>
      RecoveryFailed ctx "No catch-up request found"
    _ =>
      RecoveryFailed ctx "Account not in recovery state"

||| Fail recovery and return to SUSPENDED
public export
abortRecovery : RecoveryContext -> String -> Nat -> RecoveryContext
abortRecovery ctx reason now =
  let newStatusCtx = failRecovery ctx.statusCtx reason now
      newCatchUp = map (\c => failCatchUp c now) ctx.catchUpReq
  in { statusCtx := newStatusCtx
     , catchUpReq := newCatchUp
     } ctx

-- =============================================================================
-- Recovery Queries
-- =============================================================================

||| Check if recovery is in progress
public export
isRecovering : RecoveryContext -> Bool
isRecovering ctx = ctx.statusCtx.status == Recovering

||| Get current recovery progress percentage (0-100)
public export
getRecoveryProgress : RecoveryContext -> Nat
getRecoveryProgress ctx =
  case ctx.catchUpReq of
    Just catchUp => syncProgress catchUp
    Nothing => 0

||| Get blocks remaining to sync
public export
getBlocksRemaining : RecoveryContext -> Nat
getBlocksRemaining ctx =
  case ctx.catchUpReq of
    Just catchUp => blocksRemaining catchUp
    Nothing => 0

||| Estimate time remaining in minutes
public export
estimateTimeRemaining : RecoveryContext -> Nat
estimateTimeRemaining ctx =
  case ctx.catchUpReq of
    Just catchUp =>
      let remaining = blocksRemaining catchUp
          batches = calcCallsNeeded remaining
      in (batches * 2) `div` 60  -- ~2 sec per HTTP call
    Nothing => 0

