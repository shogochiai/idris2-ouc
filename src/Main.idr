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
|||
||| Commands (Update):
||| - 10: Register auditor (simple test version)
||| - 11: Suspend auditor (by index in arg[1])
||| - 12: Reactivate auditor (by index in arg[1])
|||
||| Result codes: 1 = success, 0 = not found, -1 = error
module Main

import OUC.Core
import AuditorPool.Core
import FRMonad.Core
import Data.IORef
import Data.List
import System

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

||| Initialize OUC state with anonymous principal
export
initialOUCState : OUCState
initialOUCState = initialState (MkICPrincipal "aaaaa-aa")

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
initGlobalState : IO ()
initGlobalState = do
  writeIORef globalStateRef (Just initialOUCState)
  setStateInitialized 1  -- Set C-backed flag (persists across calls)
  setResult 1  -- Signal success to C

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

-- Update commands (10+)
CMD_REGISTER_AUDITOR : Int
CMD_REGISTER_AUDITOR = 10

CMD_SUSPEND_AUDITOR : Int
CMD_SUSPEND_AUDITOR = 11

CMD_REACTIVATE_AUDITOR : Int
CMD_REACTIVATE_AUDITOR = 12

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

||| Dispatch command and write result
||| C sets arg[0] = command, calls main/dispatch, reads result
||| NOTE: == operator fixed in Idris2 PR #3708 for RefC/WASM32.
||| Using case for pattern matching style consistency.
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
    -- Update commands (10+)
    10 => doRegisterAuditor                 -- CMD_REGISTER_AUDITOR
    11 => doSuspendAuditor                  -- CMD_SUSPEND_AUDITOR
    12 => doReactivateAuditor               -- CMD_REACTIVATE_AUDITOR
    _  => setResult (-1)                    -- Unknown command

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Main expression - called by canister_init
||| Dispatches based on command set in arg[0]
main : IO ()
main = dispatchCommand
