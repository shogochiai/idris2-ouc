||| A-Life Economics - Account Status State Machine
|||
||| Manages operational status of protocol accounts:
|||   ACTIVE     - Normal operation, all queries/updates allowed
|||   SUSPENDED  - Cycles depleted, query only, no sync
|||   RECOVERING - Catch-up sync in progress after revival
|||
||| State transitions:
|||   ACTIVE → SUSPENDED (cycles depleted)
|||   SUSPENDED → RECOVERING (donation received, starting catch-up)
|||   RECOVERING → ACTIVE (catch-up completed)
|||   RECOVERING → SUSPENDED (catch-up failed or cycles depleted during)
|||
||| This implements ECON-006, ECON-007 from docs/ecosystem.md
module Economics.Status

import Economics.Tier
import Economics.Types
import Economics.Treasury
import Data.Nat

%default total

-- =============================================================================
-- Account Status
-- =============================================================================

||| Operational status of a protocol account
public export
data AccountStatus
  = Active        -- Normal operation
  | Suspended     -- Cycles depleted, query-only mode
  | Recovering    -- Catch-up sync in progress

public export
Show AccountStatus where
  show Active = "ACTIVE"
  show Suspended = "SUSPENDED"
  show Recovering = "RECOVERING"

public export
Eq AccountStatus where
  Active == Active = True
  Suspended == Suspended = True
  Recovering == Recovering = True
  _ == _ = False

||| Serialize status
public export
serializeStatus : AccountStatus -> String
serializeStatus Active = "0"
serializeStatus Suspended = "1"
serializeStatus Recovering = "2"

||| Deserialize status
public export
deserializeStatus : String -> Maybe AccountStatus
deserializeStatus "0" = Just Active
deserializeStatus "1" = Just Suspended
deserializeStatus "2" = Just Recovering
deserializeStatus _ = Nothing

-- =============================================================================
-- Recovery Progress
-- =============================================================================

||| Progress of catch-up sync during recovery
public export
record RecoveryProgress where
  constructor MkRecoveryProgress
  ||| Total blocks to sync
  totalBlocks    : Nat
  ||| Blocks synced so far
  syncedBlocks   : Nat
  ||| Estimated cycles cost
  estimatedCost  : Nat
  ||| Cycles spent so far
  cyclesSpent    : Nat
  ||| Started at timestamp
  startedAt      : Nat

||| Calculate sync progress percentage (0-100)
public export
syncProgressPercent : RecoveryProgress -> Nat
syncProgressPercent p = pctValue (calcPercentage p.syncedBlocks p.totalBlocks)

public export
Show RecoveryProgress where
  show p = "Recovery{" ++ show (syncProgressPercent p) ++ "%, "
        ++ show p.syncedBlocks ++ "/" ++ show p.totalBlocks ++ " blocks}"

||| Initial recovery progress
public export
initialProgress : Nat -> Nat -> Nat -> RecoveryProgress
initialProgress totalBlocks estimatedCost now =
  MkRecoveryProgress totalBlocks 0 estimatedCost 0 now

||| Update progress after sync batch
public export
updateProgress : RecoveryProgress -> Nat -> Nat -> RecoveryProgress
updateProgress p blocksSynced cyclesUsed =
  { syncedBlocks := p.syncedBlocks + blocksSynced
  , cyclesSpent := p.cyclesSpent + cyclesUsed
  } p

||| Check if recovery is complete
public export
isRecoveryComplete : RecoveryProgress -> Bool
isRecoveryComplete p = p.syncedBlocks >= p.totalBlocks

-- =============================================================================
-- Status Context
-- =============================================================================

||| Full status context for an account
public export
record StatusContext where
  constructor MkStatusContext
  ||| Current operational status
  status         : AccountStatus
  ||| Recovery progress (only valid when Recovering)
  recovery       : Maybe RecoveryProgress
  ||| Cycles available for operations
  availableCycles : Nat
  ||| Minimum cycles required to operate
  minCyclesRequired : Nat
  ||| Last status change timestamp
  statusChangedAt : Nat

||| Create initial active status
public export
initialStatusContext : Nat -> StatusContext
initialStatusContext now =
  MkStatusContext Active Nothing 0 1_000_000_000 now  -- 1B cycles minimum

public export
Show StatusContext where
  show ctx = "Status{" ++ show ctx.status
          ++ ", cycles=" ++ show ctx.availableCycles
          ++ case ctx.recovery of
               Nothing => ""
               Just p => ", " ++ show p
          ++ "}"

-- =============================================================================
-- Operation Checks
-- =============================================================================

||| Check if account can perform operations (has enough cycles)
public export
canOperate : StatusContext -> Bool
canOperate ctx = ctx.availableCycles >= ctx.minCyclesRequired

||| Check if queries are allowed (always allowed except severe suspension)
public export
canQuery : StatusContext -> Bool
canQuery _ = True  -- Queries always allowed

||| Check if updates/syncs are allowed
public export
canSync : StatusContext -> Bool
canSync ctx = case ctx.status of
  Active => canOperate ctx
  Suspended => False
  Recovering => canOperate ctx  -- Can sync during recovery

-- =============================================================================
-- Status Transitions
-- =============================================================================

||| Result of a status check
public export
data StatusCheckResult
  = StatusOk StatusContext
  | StatusSuspended StatusContext String  -- reason
  | StatusRecovering StatusContext RecoveryProgress

||| Check cycles and potentially suspend
public export
checkCyclesAndSuspend :
  StatusContext ->
  Nat ->              -- currentCycles
  Nat ->              -- currentTime
  StatusCheckResult
checkCyclesAndSuspend ctx currentCycles now =
  let updatedCtx = { availableCycles := currentCycles } ctx
  in if currentCycles < ctx.minCyclesRequired && ctx.status == Active
     then -- Transition to Suspended
       let suspended = { status := Suspended
                       , statusChangedAt := now
                       } updatedCtx
       in StatusSuspended suspended "Cycles depleted"
     else StatusOk updatedCtx

||| Start recovery process (SUSPENDED → RECOVERING)
public export
startRecovery :
  StatusContext ->
  Nat ->              -- blocksToSync
  Nat ->              -- estimatedCost
  Nat ->              -- currentTime
  Maybe StatusContext
startRecovery ctx blocksToSync estimatedCost now =
  case ctx.status of
    Suspended =>
      let progress = initialProgress blocksToSync estimatedCost now
      in Just $ MkStatusContext
           Recovering
           (Just progress)
           ctx.availableCycles
           ctx.minCyclesRequired
           now
    _ => Nothing  -- Can only start recovery from Suspended

||| Update recovery progress
public export
updateRecovery :
  StatusContext ->
  Nat ->              -- blocksSynced
  Nat ->              -- cyclesUsed
  Nat ->              -- currentTime
  StatusContext
updateRecovery ctx blocksSynced cyclesUsed now =
  case (ctx.status, ctx.recovery) of
    (Recovering, Just progress) =>
      let newProgress = updateProgress progress blocksSynced cyclesUsed
          newCycles = if ctx.availableCycles >= cyclesUsed
                      then ctx.availableCycles `minus` cyclesUsed
                      else 0
      in if isRecoveryComplete newProgress
         then -- Transition to Active
           MkStatusContext Active Nothing newCycles ctx.minCyclesRequired now
         else -- Continue recovering
           { recovery := Just newProgress
           , availableCycles := newCycles
           , statusChangedAt := now
           } ctx
    _ => ctx  -- No change if not recovering

||| Complete recovery (RECOVERING → ACTIVE)
public export
completeRecovery :
  StatusContext ->
  Nat ->              -- currentTime
  StatusContext
completeRecovery ctx now =
  case ctx.status of
    Recovering => MkStatusContext Active Nothing ctx.availableCycles ctx.minCyclesRequired now
    _ => ctx

||| Fail recovery back to Suspended
public export
failRecovery :
  StatusContext ->
  String ->           -- reason
  Nat ->              -- currentTime
  StatusContext
failRecovery ctx reason now =
  case ctx.status of
    Recovering => MkStatusContext Suspended Nothing ctx.availableCycles ctx.minCyclesRequired now
    _ => ctx

-- =============================================================================
-- Top-up Triggers
-- =============================================================================

||| Check if cycles top-up should be triggered
||| Uses Treasury watermark logic
public export
shouldTriggerTopUp :
  StatusContext ->
  Nat ->              -- lowWatermark
  Bool
shouldTriggerTopUp ctx lowWatermark =
  ctx.availableCycles < lowWatermark

||| Calculate top-up amount needed
public export
calculateTopUpAmount :
  StatusContext ->
  Nat ->              -- highWatermark
  Nat
calculateTopUpAmount ctx highWatermark =
  if ctx.availableCycles < highWatermark
  then highWatermark `minus` ctx.availableCycles
  else 0

-- =============================================================================
-- Serialization
-- =============================================================================

||| Serialize StatusContext to string
public export
serializeStatusContext : StatusContext -> String
serializeStatusContext ctx =
  serializeStatus ctx.status ++ "|" ++
  show ctx.availableCycles ++ "|" ++
  show ctx.minCyclesRequired ++ "|" ++
  show ctx.statusChangedAt ++ "|" ++
  (case ctx.recovery of
    Nothing => "none"
    Just p => show p.totalBlocks ++ ":" ++ show p.syncedBlocks)

-- =============================================================================
-- Integration with Treasury
-- =============================================================================

||| Update status context from Treasury state
public export
updateFromTreasury :
  StatusContext ->
  Treasury ->
  Nat ->              -- currentTime
  StatusCheckResult
updateFromTreasury ctx treasury now =
  let currentCycles = if treasury.operating.availableCycles >= 0
                      then fromInteger treasury.operating.availableCycles
                      else 0
  in checkCyclesAndSuspend ctx currentCycles now
