||| FFI Bug #3 Minimal Reproduction Case
|||
||| This module tests Idris2 RefC FFI round-trip behavior.
||| Expected: FFI calls return correct values.
||| Bug #3: FFI calls return 0 instead of actual values.
|||
||| This is a minimal test that avoids I/O operations to simplify linking.
module FFITest

%default total

-- =============================================================================
-- FFI Declarations
-- =============================================================================

-- Test 1: Return constant 42
%foreign "C:ffi_return_42,libffitest"
prim__return42 : PrimIO Int

-- Test 2: Return argument + 1
%foreign "C:ffi_add_one,libffitest"
prim__addOne : Int -> PrimIO Int

-- Test 3: Set/Get pattern (like OUC)
%foreign "C:ffi_set_result,libffitest"
prim__setResult : Int -> PrimIO ()

%foreign "C:ffi_get_result,libffitest"
prim__getResult : PrimIO Int

-- Test 5: Round-trip test
%foreign "C:ffi_roundtrip,libffitest"
prim__roundtrip : Int -> PrimIO Int

-- Debug print (C-side)
%foreign "C:ffi_debug_int,libffitest"
prim__debugInt : String -> Int -> PrimIO ()

-- =============================================================================
-- IO Wrappers
-- =============================================================================

export
return42 : IO Int
return42 = primIO prim__return42

export
addOne : Int -> IO Int
addOne x = primIO $ prim__addOne x

export
setResult : Int -> IO ()
setResult x = primIO $ prim__setResult x

export
getResult : IO Int
getResult = primIO prim__getResult

export
roundtrip : Int -> IO Int
roundtrip x = primIO $ prim__roundtrip x

export
debugInt : String -> Int -> IO ()
debugInt msg x = primIO $ prim__debugInt msg x

-- =============================================================================
-- Test Runner (minimal - returns exit code)
-- =============================================================================

||| Run all FFI tests, return number of failures
export covering
runTests : IO Int
runTests = do
  -- Test 1: return42 should return 42
  r1 <- return42
  debugInt "Test1 return42" r1
  let f1 = if r1 == 42 then 0 else 1

  -- Test 2: addOne(10) should return 11
  r2 <- addOne 10
  debugInt "Test2 addOne(10)" r2
  let f2 = if r2 == 11 then 0 else 1

  -- Test 3: setResult(100), getResult should return 100
  setResult 100
  r3 <- getResult
  debugInt "Test3 getResult" r3
  let f3 = if r3 == 100 then 0 else 1

  -- Test 4: roundtrip(20) should return 30
  r4 <- roundtrip 20
  debugInt "Test4 roundtrip(20)" r4
  let f4 = if r4 == 30 then 0 else 1

  -- Return failure count
  pure (f1 + f2 + f3 + f4)

-- =============================================================================
-- Main Entry Point
-- =============================================================================

covering
main : IO ()
main = do
  failures <- runTests
  debugInt "Total failures" failures
  -- Exit with failure count (0 = success)
  pure ()
