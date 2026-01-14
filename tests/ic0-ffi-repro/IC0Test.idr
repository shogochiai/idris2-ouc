||| IC0 FFI Bug #3 Reproduction Case
|||
||| This module tests Idris2 RefC FFI behavior with IC0 System API.
||| The goal is to reproduce Bug #3 in the ICP environment.
|||
||| Test Strategy:
||| 1. Call IC0 function that returns a value (e.g., ic0_time)
||| 2. Capture the return value in Idris2
||| 3. Return it via msg_reply for verification
|||
||| Expected: Return value matches IC0 function output
||| Bug #3: Return value is 0 regardless of actual value
module IC0Test

%default total

-- =============================================================================
-- IC0 System API FFI Declarations
-- =============================================================================

-- ic0.time() returns nanoseconds since epoch (uint64)
%foreign "C:ic0_time,libic0"
prim__ic0Time : PrimIO Int

-- Debug print to replica logs
%foreign "C:ic0_debug_print,libic0"
prim__debugPrint : Int -> Int -> PrimIO ()

-- Message reply
%foreign "C:ic0_msg_reply,libic0"
prim__msgReply : PrimIO ()

%foreign "C:ic0_msg_reply_data_append,libic0"
prim__msgReplyDataAppend : Int -> Int -> PrimIO ()

-- =============================================================================
-- Test FFI Functions (C-backed, for comparison)
-- =============================================================================

-- Direct IC0 call from C (bypass Idris2 FFI for return value)
%foreign "C:test_get_time_direct,libic0"
prim__getTimeDirect : PrimIO Int

-- Set/Get pattern (like OUC workaround)
%foreign "C:test_set_result,libic0"
prim__setResult : Int -> PrimIO ()

%foreign "C:test_get_result,libic0"
prim__getResult : PrimIO Int

-- Debug integer to replica log
%foreign "C:test_debug_int,libic0"
prim__debugInt : Int -> PrimIO ()

-- =============================================================================
-- IO Wrappers
-- =============================================================================

export
getTimeIdris : IO Int
getTimeIdris = primIO prim__ic0Time

export
getTimeDirect : IO Int
getTimeDirect = primIO prim__getTimeDirect

export
setResult : Int -> IO ()
setResult x = primIO $ prim__setResult x

export
getResult : IO Int
getResult = primIO prim__getResult

export
debugInt : Int -> IO ()
debugInt x = primIO $ prim__debugInt x

export
msgReply : IO ()
msgReply = primIO prim__msgReply

export
msgReplyDataAppend : Int -> Int -> IO ()
msgReplyDataAppend ptr size = primIO $ prim__msgReplyDataAppend ptr size

-- =============================================================================
-- Test Harness
-- =============================================================================

||| Run FFI test and store results
||| Returns: 0 = success, non-zero = failure count
export covering
runTest : IO Int
runTest = do
  -- Test 1: Get time via Idris2 FFI (Bug #3 target)
  timeIdris <- getTimeIdris
  debugInt timeIdris  -- Log: should be non-zero nanoseconds

  -- Test 2: Get time via C direct call (workaround)
  timeDirect <- getTimeDirect
  debugInt timeDirect  -- Log: should be non-zero nanoseconds

  -- Test 3: Compare values
  -- If Bug #3 is present: timeIdris == 0, timeDirect != 0
  -- If working correctly: both should be similar (within a few ms)

  -- Store results for reply
  setResult timeIdris

  -- Calculate pass/fail
  let idrisWorking = if timeIdris > 0 then 1 else 0
  let directWorking = if timeDirect > 0 then 1 else 0

  -- Return failure count
  -- 0 = both working, 1 = one failed, 2 = both failed
  pure (2 - idrisWorking - directWorking)

-- =============================================================================
-- Entry Point (called from C canister_query handler)
-- =============================================================================

covering
main : IO ()
main = do
  failures <- runTest
  debugInt failures
  -- Reply with failure count
  pure ()
