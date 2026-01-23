||| OUC Canister Main Entry Point
|||
||| This module provides the main expression that initializes the canister.
||| The C entry points in canister_entry.c call __mainExpression_0()
||| which executes this main function.
|||
||| FFI Strategy:
||| - C sets command in ouc_arg_i32[0]
||| - C calls __mainExpression_0() (or future dispatch entry)
||| - Idris2 reads command, performs operation, writes result to ouc_result_i32
||| - C reads result from ouc_c_get_result_i32()
|||
||| Commands (Query):
||| - 0: Initialize state (called during canister_init)
||| - 1: Get version (returns 1)
||| - 2: Get proposal count
||| - 3: Get auditor count
||| - 4: Get proposal by ID (arg[1] = proposal ID)
|||
||| Commands (Update):
||| - 10: Register auditor (simple test version)
||| - 11: Suspend auditor (by index in arg[1])
||| - 12: Reactivate auditor (by index in arg[1])
|||
||| Commands (Economics/Timer):
||| - 20: Heartbeat (arg[1] = timestamp) - daily tier processing
||| - 21: Get scheduler stats (arg[1] = timestamp)
||| - 22: Register protocol (arg[1] = chainId, arg[2] = timestamp)
||| - 23: Donate to protocol (arg[1] = index, arg[2] = amount, arg[3] = timestamp)
|||
||| Result codes: 1 = success, 0 = not found, -1 = error
module Main

import OUC.Functions.Core
import OUC.Types.Validated.Address
import OUC.Types.Validated.Proposal
import AuditorPool.Core
import FRMonad.Core
import Economics.Tier
import Economics.ProtocolAccount
import Economics.Scheduler
import MultiChain.Registry
import Candid.FFI
import Candid.Chain
import Data.Bits
import Data.IORef
import Data.List
import System
-- Indexer Integration (SQLite-only storage)
import Core as Indexer
import StorageSql as SqlStorage
import StorageApi
import Indexer.OucIndexerAdapter

%default total

-- =============================================================================
-- FFI: C<->Idris2 Communication
-- These use %foreign to access C globals in ic0_stubs.c
-- =============================================================================

-- Write result to C global (for C to read after call)
-- Note: Using Int instead of Int32 for RefC backend compatibility
%foreign "C:ouc_set_result_i32,libic0"
prim__setResultI32 : Int -> PrimIO ()

-- Read argument from C global (set by C before call)
%foreign "C:ouc_get_arg_i32,libic0"
prim__getArgI32 : Int -> PrimIO Int

-- State initialization flag (C-backed, persistent across calls)
%foreign "C:ouc_set_state_initialized,libic0"
prim__setStateInitialized : Int -> PrimIO ()

%foreign "C:ouc_get_state_initialized,libic0"
prim__getStateInitialized : PrimIO Int

-- IO wrappers
setResult : Int -> IO ()
setResult n = primIO $ prim__setResultI32 n

getArg : Int -> IO Int
getArg idx = primIO $ prim__getArgI32 idx

setStateInitialized : Int -> IO ()
setStateInitialized n = primIO $ prim__setStateInitialized n

getStateInitialized : IO Int
getStateInitialized = primIO prim__getStateInitialized

-- Auditor count (C-backed, persistent across calls)
%foreign "C:ouc_get_auditor_count,libic0"
prim__getAuditorCount : PrimIO Int

%foreign "C:ouc_inc_auditor_count,libic0"
prim__incAuditorCount : PrimIO Int

getCBackedAuditorCount : IO Int
getCBackedAuditorCount = primIO prim__getAuditorCount

||| Increment auditor count and return the new count
||| Returns Int to force execution (prevents optimization)
incCBackedAuditorCount : IO Int
incCBackedAuditorCount = primIO prim__incAuditorCount

-- =============================================================================
-- Global State Management
-- =============================================================================

||| Global mutable state reference (initialized in canister_init)
%noinline
globalStateRef : IORef (Maybe OUCState)
globalStateRef = unsafePerformIO $ newIORef Nothing

||| Global Economics state references
%noinline
globalAccountRegistryRef : IORef AccountRegistry
globalAccountRegistryRef = unsafePerformIO $ newIORef Economics.ProtocolAccount.emptyRegistry

%noinline
globalSchedulerRef : IORef SchedulerState
globalSchedulerRef = unsafePerformIO $ newIORef initialSchedulerState

-- SQLite backend state (for persistent storage)
-- Note: All indexer data stored in SQLite, no in-memory fallback
%noinline
globalSqlStateRef : IORef (Maybe SqlStorage.SqlBackendState)
globalSqlStateRef = unsafePerformIO $ newIORef Nothing

||| Initialize OUC state with anonymous principal
export
initialOUCState : OUCState
initialOUCState = initialState (unsafeMkPrincipal "aaaaa-aa")

-- =============================================================================
-- Query Functions (read from global state)
-- =============================================================================

||| Get OUC version
export
getOucVersion : IO Nat
getOucVersion = pure 1

||| Get proposal count from global state
export
getProposalCount : IO Nat
getProposalCount = do
  mstate <- readIORef globalStateRef
  pure $ case mstate of
    Nothing => 0
    Just st => length st.proposals

||| Get auditor count from C-backed storage (persistent across calls)
export
getAuditorCount : IO Nat
getAuditorCount = do
  count <- getCBackedAuditorCount
  pure (cast count)

-- =============================================================================
-- State Initialization
-- =============================================================================

||| Initialize global state and set result to 1 (success)
export
covering
initGlobalState : IO ()
initGlobalState = do
  writeIORef globalStateRef (Just initialOUCState)
  -- Initialize SQLite backend for indexer persistence
  sqlResult <- SqlStorage.initSqlBackend
  case sqlResult of
    StorageOk sqlState => do
      writeIORef globalSqlStateRef (Just sqlState)
      setStateInitialized 1  -- Set C-backed flag (persists across calls)
      setResult 1  -- Signal success to C
    StorageError err => do
      -- SQLite init failed - this is a critical error
      setStateInitialized 0
      setResult (-1)  -- Signal failure to C

||| Ensure state is initialized before operations
||| Re-initializes IORef from C flag if needed (IORef doesn't persist in WASM)
ensureState : IO (Maybe OUCState)
ensureState = do
  initialized <- getStateInitialized
  case initialized of
    1 => do
      -- C flag says we're initialized, but IORef might be Nothing (new call)
      -- Re-initialize IORef if needed
      mstate <- readIORef globalStateRef
      case mstate of
        Nothing => do
          -- Re-initialize IORef from C state
          writeIORef globalStateRef (Just initialOUCState)
          pure (Just initialOUCState)
        Just st => pure (Just st)
    _ => pure Nothing  -- Not initialized

-- =============================================================================
-- Command Dispatch
-- =============================================================================

||| Command constants (must match canister_entry.c)
CMD_INIT : Int
CMD_INIT = 0

CMD_GET_VERSION : Int
CMD_GET_VERSION = 1

CMD_GET_PROPOSAL_COUNT : Int
CMD_GET_PROPOSAL_COUNT = 2

CMD_GET_AUDITOR_COUNT : Int
CMD_GET_AUDITOR_COUNT = 3

CMD_GET_PROPOSAL : Int
CMD_GET_PROPOSAL = 4

-- Update commands (10+)
CMD_REGISTER_AUDITOR : Int
CMD_REGISTER_AUDITOR = 10

CMD_SUSPEND_AUDITOR : Int
CMD_SUSPEND_AUDITOR = 11

CMD_REACTIVATE_AUDITOR : Int
CMD_REACTIVATE_AUDITOR = 12

CMD_SUBMIT_PROPOSAL : Int
CMD_SUBMIT_PROPOSAL = 13

-- Timer/Heartbeat commands (20+)
CMD_HEARTBEAT : Int
CMD_HEARTBEAT = 20

CMD_GET_SCHEDULER_STATS : Int
CMD_GET_SCHEDULER_STATS = 21

CMD_REGISTER_PROTOCOL : Int
CMD_REGISTER_PROTOCOL = 22

CMD_DONATE_TO_PROTOCOL : Int
CMD_DONATE_TO_PROTOCOL = 23

-- Indexer Query commands (30+)
CMD_GET_OUC_EVENTS : Int
CMD_GET_OUC_EVENTS = 30

CMD_GET_PROPOSAL_EVENTS : Int
CMD_GET_PROPOSAL_EVENTS = 31

CMD_GET_DASHBOARD_SUMMARY : Int
CMD_GET_DASHBOARD_SUMMARY = 32

CMD_STORE_TEST_EVENT : Int
CMD_STORE_TEST_EVENT = 33

-- =============================================================================
-- Query Functions (by ID)
-- =============================================================================

||| Get proposal by ID
||| Returns: 1 = found, 0 = not found, -1 = error
||| Note: For MVP, just checks if ID is valid (< proposal count)
doGetProposal : IO ()
doGetProposal = do
  proposalId <- getArg 1
  mstate <- ensureState
  case mstate of
    Nothing => setResult (-1)  -- State not initialized
    Just st => do
      let proposals = st.proposals
      if cast proposalId < length proposals
        then setResult 1  -- Found
        else setResult 0  -- Not found

-- =============================================================================
-- Update Functions (modify global state)
-- =============================================================================

||| Register a test auditor with the caller's principal
||| Returns: 1 = success, 0 = already exists, -1 = error
||| MVP: Simply increments C-backed auditor count (no duplicate check)
doRegisterAuditor : IO ()
doRegisterAuditor = do
  initialized <- getStateInitialized
  case initialized of
    1 => do
      newCount <- incCBackedAuditorCount  -- Returns new count (forces execution)
      -- Use newCount to prevent optimization from eliminating the call
      setResult (if newCount > 0 then 1 else 1)  -- Success
    _ => setResult (-1)  -- State not initialized

||| Suspend auditor by index (arg[1] = index)
||| Returns: 1 = success, 0 = not found, -1 = error
doSuspendAuditor : IO ()
doSuspendAuditor = do
  idx <- getArg 1
  mstate <- ensureState
  case mstate of
    Nothing => setResult (-1)
    Just st => do
      let auditors = st.auditors
      if cast idx >= length auditors
        then setResult 0  -- Not found
        else do
          -- Use AuditorPool.Core.suspendAuditor (needs auditor ID)
          case getAt (cast idx) auditors of
            Nothing => setResult 0
            Just auditor => do
              case suspendAuditor auditors auditor.id "Suspended via canister call" of
                Fail _ _ => setResult (-1)
                Ok newAuditors _ => do
                  let newState = { auditors := newAuditors } st
                  writeIORef globalStateRef (Just newState)
                  setResult 1

||| Reactivate auditor by index (arg[1] = index)
||| Returns: 1 = success, 0 = not found, -1 = error
doReactivateAuditor : IO ()
doReactivateAuditor = do
  idx <- getArg 1
  mstate <- ensureState
  case mstate of
    Nothing => setResult (-1)
    Just st => do
      let auditors = st.auditors
      if cast idx >= length auditors
        then setResult 0
        else do
          case getAt (cast idx) auditors of
            Nothing => setResult 0
            Just auditor => do
              case reactivateAuditor auditors auditor.id of
                Fail _ _ => setResult (-1)
                Ok newAuditors _ => do
                  let newState = { auditors := newAuditors } st
                  writeIORef globalStateRef (Just newState)
                  setResult 1

||| Submit a new upgrade proposal
||| Returns: proposal ID (>=0) on success, -1 on error
||| MVP: Uses dummy values for chain, target, etc. (rationale comes from C but not passed yet)
doSubmitProposal : IO ()
doSubmitProposal = do
  mstate <- ensureState
  case mstate of
    Nothing => setResult (-1)  -- State not initialized
    Just st => do
      -- MVP: Use dummy values for required parameters
      let chainId = MkChainId 1  -- Ethereum mainnet
          target = unsafeMkEvmAddress "0000000000000000000000000000000000000000"
          newImpl = unsafeMkEvmAddress "0000000000000000000000000000000000000001"
          ou = unsafeMkEvmAddress "0000000000000000000000000000000000000002"  -- OU address
          proposer = unsafeMkPrincipal "aaaaa-aa"
          rationale = "MVP test proposal"  -- TODO: Pass from C
          codeHash = "0x0"
          now = 0  -- Nat timestamp (nanoseconds)
      case submitProposal st chainId target newImpl ou proposer rationale codeHash now of
        Fail _ _ => setResult (-1)
        Ok (newState, pid) _ => do
          writeIORef globalStateRef (Just newState)
          setResult (cast pid.value)  -- Return proposal ID

-- =============================================================================
-- Economics Functions (Timer/Heartbeat)
-- =============================================================================

||| Process heartbeat - called by canister timer
||| arg[1] = current timestamp (seconds)
||| Returns: number of accounts processed
doHeartbeat : IO ()
doHeartbeat = do
  initialized <- getStateInitialized
  case initialized of
    1 => do
      timestamp <- getArg 1
      sched <- readIORef globalSchedulerRef
      reg <- readIORef globalAccountRegistryRef
      let result = processHeartbeat sched reg (cast timestamp)
      writeIORef globalSchedulerRef result.scheduler
      writeIORef globalAccountRegistryRef result.registry
      setResult (cast result.accountsProcessed)
    _ => setResult (-1)

||| Get scheduler statistics
||| arg[1] = current timestamp (seconds)
||| Returns: pending sync count
doGetSchedulerStats : IO ()
doGetSchedulerStats = do
  timestamp <- getArg 1
  sched <- readIORef globalSchedulerRef
  reg <- readIORef globalAccountRegistryRef
  let stats = getSchedulerStats sched reg (cast timestamp)
  setResult (cast stats.pendingSyncs)

||| Register a new protocol for monitoring
||| arg[1] = chain ID
||| Uses dummy address for MVP (real impl would read address from C buffer)
||| Returns: 1 = success
doRegisterProtocol : IO ()
doRegisterProtocol = do
  initialized <- getStateInitialized
  case initialized of
    1 => do
      chainIdArg <- getArg 1
      timestamp <- getArg 2
      reg <- readIORef globalAccountRegistryRef
      -- MVP: Generate dummy address based on account count
      let addrHex = "0x" ++ pack (replicate 40 '0')  -- Placeholder
          addr = MkEvmAddress addrHex
          chainId = MkChainId (cast chainIdArg)
          newAcc = createAccount addr chainId (cast timestamp)
          newReg = upsertAccount reg newAcc (cast timestamp)
      writeIORef globalAccountRegistryRef newReg
      setResult 1
    _ => setResult (-1)

||| Donate cycles to a protocol
||| arg[1] = protocol index in registry
||| arg[2] = amount (small value for testing)
||| arg[3] = current timestamp
||| Returns: new tier (0=Archive, 1=Economy, 2=Standard, 3=RealTime)
doDonateToProtocol : IO ()
doDonateToProtocol = do
  initialized <- getStateInitialized
  case initialized of
    1 => do
      idx <- getArg 1
      amount <- getArg 2
      timestamp <- getArg 3
      reg <- readIORef globalAccountRegistryRef
      case getAt (cast idx) reg.accounts of
        Nothing => setResult (-1)  -- Protocol not found
        Just acc => do
          let result = donate acc (cast amount) (cast timestamp)
              tierNum : Int = case result.newTier of
                Archive  => 0
                Economy  => 1
                Standard => 2
                RealTime => 3
          writeIORef globalAccountRegistryRef (upsertAccount reg result.account (cast timestamp))
          setResult tierNum
    _ => setResult (-1)

-- =============================================================================
-- Candid Encoding Commands
-- =============================================================================

||| Encode EVM RPC request to Candid buffer
||| arg[1] = chainId (1=EthMainnet, 11155111=Sepolia, 8453=Base, 42161=Arbitrum)
||| arg[2] = maxResponseBytes (low 32 bits)
||| JSON is read from ouc_json_buf (set by C via ouc_c_set_json)
||| Result written to ouc_candid_buf, length returned in result
||| Returns: length of encoded Candid, or -1 if unknown chain
doEncodeEvmRpc : IO ()
doEncodeEvmRpc = do
  chainIdArg <- getArg 1
  maxBytesArg <- getArg 2
  let chainId : Int32 = cast chainIdArg
      maxBytes : Bits64 = cast maxBytesArg
  result <- encodeEvmRpcFromBuffer chainId maxBytes
  setResult result

-- =============================================================================
-- Indexer Query Functions
-- =============================================================================

||| Get recent OUC events
||| arg[1] = limit (max events to return)
||| Returns: count of events (actual data would be in response buffer)
covering
doGetOucEvents : IO ()
doGetOucEvents = do
  limitArg <- getArg 1
  let limit : Nat = if limitArg <= 0 then 10 else integerToNat (cast limitArg)
  -- Query from SQLite (no fallback)
  sqlResult <- SqlStorage.sqlQueryEvents Indexer.emptyFilter 0 limit
  case sqlResult of
    StorageOk page => setResult (cast $ length page.events)
    StorageError _ => setResult (-1)  -- SQLite error

||| Get events for a specific proposal
||| arg[1] = proposalId
||| Returns: count of vote events for this proposal
covering
doGetProposalEvents : IO ()
doGetProposalEvents = do
  proposalId <- getArg 1
  let pid : Nat = integerToNat (cast proposalId)
  -- Query VoteCast events filtered by topic (proposalId is in topic1)
  -- For now, query all VoteCast events and filter
  let voteFilter = { topic0 := Just voteCastTopic } Indexer.emptyFilter
  sqlResult <- SqlStorage.sqlQueryEvents voteFilter 0 1000
  case sqlResult of
    StorageOk page => setResult (cast $ length page.events)
    StorageError _ => setResult (-1)  -- SQLite error

||| Get dashboard summary (aggregated stats)
||| Returns: total event count in indexer
covering
doGetDashboardSummary : IO ()
doGetDashboardSummary = do
  -- Query from SQLite (no fallback)
  sqlResult <- SqlStorage.sqlGetStorageInfo
  case sqlResult of
    StorageOk info => setResult (cast info.eventCount)
    StorageError _ => setResult (-1)  -- SQLite error

||| Store a test event (for development/testing)
||| arg[1] = blockNumber
||| arg[2] = eventType (0=UpgradeProposed, 1=VoteCast, 2=ProposalExecuted)
||| Returns: new event count
covering
doStoreTestEvent : IO ()
doStoreTestEvent = do
  blockNum <- getArg 1
  eventType <- getArg 2
  -- Get current event count from SQLite for event ID
  infoResult <- SqlStorage.sqlGetStorageInfo
  let nextId : Nat = case infoResult of
        StorageOk info => info.eventCount
        StorageError _ => 0
  let blockNat : Nat = integerToNat (cast blockNum)
      topic = case eventType of
        0 => upgradeProposedTopic
        1 => voteCastTopic
        2 => proposalExecutedTopic
        _ => upgradeProposedTopic
      testEvent = Indexer.MkIndexedEvent
        nextId                          -- eventId
        Indexer.ethereumMainnet         -- chainId
        blockNat                        -- blockNumber
        Indexer.zeroBytes32             -- blockHash
        Indexer.zeroBytes32             -- txHash
        0                               -- txIndex
        0                               -- logIndex
        Indexer.zeroAddress             -- address
        topic                           -- topic0
        Nothing                         -- topic1
        Nothing                         -- topic2
        Nothing                         -- topic3
        ""                              -- data_
        blockNat                        -- timestamp
        0                               -- indexedAt
  -- Store to SQLite (no fallback)
  sqlResult <- SqlStorage.sqlStoreEvent testEvent
  case sqlResult of
    StorageOk newId => do
      -- Return new count from SQLite
      newInfoResult <- SqlStorage.sqlGetStorageInfo
      case newInfoResult of
        StorageOk info => setResult (cast info.eventCount)
        StorageError _ => setResult (cast $ nextId + 1)  -- Estimate
    StorageError _ => setResult (-1)  -- SQLite error

||| Dispatch command and write result
||| C sets arg[0] = command, calls main/dispatch, reads result
||| NOTE: == operator fixed in Idris2 PR #3708 for RefC/WASM32.
||| Using case for pattern matching style consistency.
covering
dispatchCommand : IO ()
dispatchCommand = do
  cmd <- getArg 0
  case cmd of
    -- Query commands (0-9)
    0 => initGlobalState                    -- CMD_INIT
    1 => setResult 1                        -- CMD_GET_VERSION
    2 => do                                 -- CMD_GET_PROPOSAL_COUNT
           count <- getProposalCount
           setResult (cast count)
    3 => do                                 -- CMD_GET_AUDITOR_COUNT
           count <- getAuditorCount
           setResult (cast count)
    4 => doGetProposal                      -- CMD_GET_PROPOSAL
    -- Update commands (10+)
    10 => doRegisterAuditor                 -- CMD_REGISTER_AUDITOR
    11 => doSuspendAuditor                  -- CMD_SUSPEND_AUDITOR
    12 => doReactivateAuditor               -- CMD_REACTIVATE_AUDITOR
    13 => doSubmitProposal                  -- CMD_SUBMIT_PROPOSAL
    -- Economics/Timer commands (20+)
    20 => doHeartbeat                       -- CMD_HEARTBEAT
    21 => doGetSchedulerStats               -- CMD_GET_SCHEDULER_STATS
    22 => doRegisterProtocol                -- CMD_REGISTER_PROTOCOL
    23 => doDonateToProtocol                -- CMD_DONATE_TO_PROTOCOL
    -- Indexer Query commands (30+)
    30 => doGetOucEvents                    -- CMD_GET_OUC_EVENTS
    31 => doGetProposalEvents               -- CMD_GET_PROPOSAL_EVENTS
    32 => doGetDashboardSummary             -- CMD_GET_DASHBOARD_SUMMARY
    33 => doStoreTestEvent                  -- CMD_STORE_TEST_EVENT
    -- Candid encoding commands (100+)
    100 => doEncodeEvmRpc                   -- CMD_ENCODE_EVM_RPC
    _  => setResult (-1)                    -- Unknown command

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main expression - called by canister_init
||| Dispatches based on command set in arg[0]
covering
main : IO ()
main = dispatchCommand
