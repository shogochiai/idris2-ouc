||| A-Life Economics - Scheduler
|||
||| Periodic task scheduler for tier management.
||| Called by canister heartbeat/timer to process daily deductions
||| and trigger scheduled syncs.
|||
||| ICP Timer Integration:
|||   - Timer interval: 1 hour (conservative)
|||   - Daily check: Compare lastProcessedDay with current day
|||   - On day change: Process all deductions
|||
||| Note: This module uses small Nat values for efficiency.
||| Actual timestamps should be converted to day numbers.
module Economics.Scheduler

import Economics.Tier
import Economics.Types
import Economics.ProtocolAccount
import MultiChain.Registry
import Data.List
import Data.Nat
import Data.Maybe

%default total

-- =============================================================================
-- Time Constants
-- =============================================================================

||| Seconds per day (for conversion)
public export
secondsPerDay : Nat
secondsPerDay = 86400

||| Nanoseconds per day
public export
nanosecondsPerDay : Nat
nanosecondsPerDay = 86400 * 1000000000

-- =============================================================================
-- Scheduler State
-- =============================================================================

||| Scheduler state for tracking periodic tasks
public export
record SchedulerState where
  constructor MkSchedulerState
  ||| Last processed day number (timestamp / secondsPerDay)
  lastProcessedDay : Nat
  ||| Total deductions processed
  totalDeductions  : Nat
  ||| Total syncs triggered
  totalSyncs       : Nat
  ||| Last heartbeat timestamp
  lastHeartbeat    : Nat

||| Initial scheduler state
public export
initialSchedulerState : SchedulerState
initialSchedulerState = MkSchedulerState 0 0 0 0

public export
Show SchedulerState where
  show s = "Scheduler{day=" ++ show s.lastProcessedDay
        ++ ", deductions=" ++ show s.totalDeductions
        ++ ", syncs=" ++ show s.totalSyncs ++ "}"

-- =============================================================================
-- Day Number Calculation
-- =============================================================================

||| Convert timestamp (seconds) to day number
||| Uses small values to avoid Nat slowness
public export
timestampToDay : Nat -> Nat
timestampToDay ts = safeDiv ts secondsPerDayNZ

||| Check if a new day has started since last processing
public export
isNewDay : SchedulerState -> Nat -> Bool
isNewDay sched currentTimestamp =
  let currentDay = timestampToDay currentTimestamp
  in currentDay > sched.lastProcessedDay

-- =============================================================================
-- Heartbeat Processing
-- =============================================================================

||| Result of a heartbeat processing
public export
record HeartbeatResult where
  constructor MkHeartbeatResult
  ||| Updated scheduler state
  scheduler       : SchedulerState
  ||| Updated account registry
  registry        : AccountRegistry
  ||| Whether daily processing was performed
  dailyProcessed  : Bool
  ||| Number of accounts processed
  accountsProcessed : Nat
  ||| Number of tier changes
  tierChanges     : Nat
  ||| Accounts due for sync
  syncsDue        : List EvmAddress

public export
Show HeartbeatResult where
  show r = "Heartbeat{daily=" ++ show r.dailyProcessed
        ++ ", accounts=" ++ show r.accountsProcessed
        ++ ", tierChanges=" ++ show r.tierChanges
        ++ ", syncsDue=" ++ show (length r.syncsDue) ++ "}"

||| Process normal tick without daily processing
processNormalTick :
  SchedulerState ->
  AccountRegistry ->
  Nat ->
  HeartbeatResult
processNormalTick sched reg currentTs =
  let -- Just find syncs due
      syncsDue = map (.protocolId) (getAccountsDueForSync reg currentTs)
      -- Update heartbeat time only
      newSched = { lastHeartbeat := currentTs } sched
  in MkHeartbeatResult
       newSched
       reg
       False
       0
       0
       syncsDue

||| Process daily tick (day changed)
||| Process all deductions and find syncs due
processDailyTick :
  SchedulerState ->
  AccountRegistry ->
  Nat ->
  Nat ->              -- currentDay
  HeartbeatResult
processDailyTick sched reg currentTs currentDay =
  let -- Process daily deductions for all accounts
      (newReg, deductResults) = processDailyDeductions reg currentTs
      -- Count tier changes
      tierChanges = length (filter (.tierDowngraded) deductResults)
      -- Find syncs due
      syncsDue = map (.protocolId) (getAccountsDueForSync newReg currentTs)
      -- Update scheduler
      newSched = MkSchedulerState
        currentDay
        (sched.totalDeductions + length deductResults)
        (sched.totalSyncs + length syncsDue)
        currentTs
  in MkHeartbeatResult
       newSched
       newReg
       True
       (length deductResults)
       tierChanges
       syncsDue

||| Process a heartbeat tick
|||
||| This is called periodically by the canister timer.
||| It checks if a new day has started and processes daily deductions.
||| It also identifies accounts that need syncing.
public export
processHeartbeat :
  SchedulerState ->
  AccountRegistry ->
  Nat ->              -- currentTimestamp (seconds)
  HeartbeatResult
processHeartbeat sched reg currentTs =
  let currentDay = timestampToDay currentTs
      needsDailyProcess = currentDay > sched.lastProcessedDay
  in if needsDailyProcess
     then processDailyTick sched reg currentTs currentDay
     else processNormalTick sched reg currentTs

-- =============================================================================
-- Sync Scheduling
-- =============================================================================

||| Get list of protocol addresses that need syncing now
public export
getProtocolsToSync :
  AccountRegistry ->
  Nat ->              -- currentTimestamp
  List EvmAddress
getProtocolsToSync reg ts =
  map (.protocolId) (getAccountsDueForSync reg ts)

||| Record that syncs were completed for given protocols
public export
recordSyncsCompleted :
  AccountRegistry ->
  List EvmAddress ->
  Nat ->              -- blockNumber
  Nat ->              -- currentTimestamp
  AccountRegistry
recordSyncsCompleted reg addrs blockNum ts =
  foldr (updateOne blockNum ts) reg addrs
  where
    updateOne : Nat -> Nat -> EvmAddress -> AccountRegistry -> AccountRegistry
    updateOne bn now addr accReg =
      case findAccount accReg addr of
        Nothing => accReg
        Just acc =>
          let updated = recordSync acc bn now
          in upsertAccount accReg updated now

-- =============================================================================
-- Statistics
-- =============================================================================

||| Get scheduler statistics
public export
record SchedulerStats where
  constructor MkSchedulerStats
  currentDay       : Nat
  totalAccounts    : Nat
  totalDeductions  : Nat
  totalSyncs       : Nat
  tierDistribution : TierDistribution
  pendingSyncs     : Nat

public export
Show SchedulerStats where
  show s = "Stats{day=" ++ show s.currentDay
        ++ ", accounts=" ++ show s.totalAccounts
        ++ ", pending=" ++ show s.pendingSyncs ++ "}"

||| Calculate scheduler statistics
public export
getSchedulerStats :
  SchedulerState ->
  AccountRegistry ->
  Nat ->              -- currentTimestamp
  SchedulerStats
getSchedulerStats sched reg currentTs =
  let pending = getAccountsDueForSync reg currentTs
      dist = getTierDistribution reg
  in MkSchedulerStats
       (timestampToDay currentTs)
       (length reg.accounts)
       sched.totalDeductions
       sched.totalSyncs
       dist
       (length pending)

-- =============================================================================
-- Batch Sync Optimization
-- =============================================================================

||| Group protocols by chain for batch syncing
public export
groupByChain : List ProtocolAccount -> List (ChainId, List EvmAddress)
groupByChain accounts =
  let -- Get unique chain IDs
      chainIds = nub (map (.chainId) accounts)
      -- Group by chain
      groupOne : ChainId -> (ChainId, List EvmAddress)
      groupOne cid =
        let matching = filter (\a => a.chainId == cid) accounts
        in (cid, map (.protocolId) matching)
  in map groupOne chainIds

||| Get batch sync tasks grouped by chain
public export
getBatchSyncTasks :
  AccountRegistry ->
  Nat ->              -- currentTimestamp
  List (ChainId, List EvmAddress)
getBatchSyncTasks reg ts =
  let due = getAccountsDueForSync reg ts
  in groupByChain due

-- =============================================================================
-- EVM Fee Sync Integration (A-Life Economics Option B)
-- =============================================================================

||| EVM Fee Registry - tracks EvmFeeState per protocol
public export
record EvmFeeRegistry where
  constructor MkEvmFeeRegistry
  ||| Map of protocol -> fee state (using list for simplicity)
  entries     : List (EvmAddress, EvmFeeState)
  ||| Last updated timestamp
  lastUpdated : Nat

||| Empty fee registry
public export
emptyFeeRegistry : EvmFeeRegistry
emptyFeeRegistry = MkEvmFeeRegistry [] 0

||| Find fee state for a protocol
public export
findFeeState : EvmFeeRegistry -> EvmAddress -> Maybe EvmFeeState
findFeeState reg protocolId =
  map snd (find (\(addr, _) => addr == protocolId) reg.entries)

||| Update fee state for a protocol
public export
upsertFeeState : EvmFeeRegistry -> EvmAddress -> EvmFeeState -> Nat -> EvmFeeRegistry
upsertFeeState reg protocolId newState now =
  let others = filter (\(addr, _) => addr /= protocolId) reg.entries
  in MkEvmFeeRegistry ((protocolId, newState) :: others) now

||| Result of processing EVM fee syncs
public export
record EvmFeeSyncBatchResult where
  constructor MkEvmFeeSyncBatchResult
  ||| Updated fee registry
  feeRegistry      : EvmFeeRegistry
  ||| Updated account registry
  accountRegistry  : AccountRegistry
  ||| Number of protocols synced
  protocolsSynced  : Nat
  ||| Total new deposits detected (wei)
  totalNewDeposits : Nat
  ||| Total cycles credited
  totalCredited    : Nat
  ||| Number of tier upgrades
  tierUpgrades     : Nat

public export
Show EvmFeeSyncBatchResult where
  show r = "FeeSyncBatch{synced=" ++ show r.protocolsSynced
        ++ ", deposits=" ++ show r.totalNewDeposits
        ++ ", credited=" ++ show r.totalCredited
        ++ ", upgrades=" ++ show r.tierUpgrades ++ "}"

||| Process a single EVM fee sync
||| Takes EVM balance read from HTTP outcall
public export
processOneEvmFeeSync :
  EvmFeeRegistry ->
  AccountRegistry ->
  EvmAddress ->         -- protocolId
  Nat ->                -- evmBalance (wei) from eth_call
  Nat ->                -- currentTime
  (EvmFeeRegistry, AccountRegistry, FeeSyncResult)
processOneEvmFeeSync feeReg accReg protocolId evmBalance now =
  let -- Get or create fee state
      feeState = fromMaybe initialEvmFeeState (findFeeState feeReg protocolId)
      -- Get or create account
      account = case findAccount accReg protocolId of
                  Just a  => a
                  Nothing => createAccount protocolId (MkChainId 1) now
      -- Sync
      result = syncEvmFeeBalance feeState account evmBalance now
      -- Update registries
      newFeeReg = upsertFeeState feeReg protocolId result.feeState now
      newAccReg = upsertAccount accReg result.account now
  in (newFeeReg, newAccReg, result)

||| Get protocols that need EVM fee sync
public export
getProtocolsForFeeSync :
  EvmFeeRegistry ->
  List EvmAddress ->    -- all known protocols
  Nat ->                -- currentTime
  List EvmAddress
getProtocolsForFeeSync feeReg protocols now =
  filter (needsSync feeReg now) protocols
  where
    needsSync : EvmFeeRegistry -> Nat -> EvmAddress -> Bool
    needsSync reg ts protocolId =
      let feeState = fromMaybe initialEvmFeeState (findFeeState reg protocolId)
      in isFeeSyncDue feeState ts feeSyncIntervalSec

||| Extended heartbeat result with EVM fee sync info
public export
record ExtendedHeartbeatResult where
  constructor MkExtendedHeartbeatResult
  ||| Basic heartbeat result
  heartbeat       : HeartbeatResult
  ||| EVM fee sync result (if performed)
  feeSyncResult   : Maybe EvmFeeSyncBatchResult
  ||| Protocols needing EVM fee sync (for HTTP outcalls)
  pendingFeeSyncs : List EvmAddress

public export
Show ExtendedHeartbeatResult where
  show r = "ExtHeartbeat{" ++ show r.heartbeat
        ++ ", feeSyncs=" ++ show (length r.pendingFeeSyncs) ++ "}"

||| Process heartbeat with EVM fee sync scheduling
|||
||| This is the main entry point for timer-based processing.
||| It:
|||   1. Processes daily deductions (if new day)
|||   2. Identifies protocols needing regular sync
|||   3. Identifies protocols needing EVM fee sync
|||
||| The actual EVM fee sync requires HTTP outcalls, so we return
||| the list of protocols needing sync. The caller should:
|||   1. Call getOUFeeBalance for each protocol via HTTP outcall
|||   2. Call processOneEvmFeeSync with the results
public export
processExtendedHeartbeat :
  SchedulerState ->
  AccountRegistry ->
  EvmFeeRegistry ->
  Nat ->                -- currentTimestamp (seconds)
  ExtendedHeartbeatResult
processExtendedHeartbeat sched accReg feeReg currentTs =
  let -- Process basic heartbeat (daily deductions, regular syncs)
      hbResult = processHeartbeat sched accReg currentTs
      -- Get protocols needing EVM fee sync
      allProtocols = map (.protocolId) accReg.accounts
      pendingFeeSyncs = getProtocolsForFeeSync feeReg allProtocols currentTs
  in MkExtendedHeartbeatResult hbResult Nothing pendingFeeSyncs
