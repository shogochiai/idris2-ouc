||| Integration Test Suite
||| These tests exercise full pipelines for OUC to maximize semantic coverage
module Integration.Tests.AllTests

import FRC.Core
import OUC.Core
import AuditorPool.Core
import Rewards.Core
import Proposals.Core
import Data.List
import Data.String

%default covering

-- =============================================================================
-- Test Helpers
-- =============================================================================

testPrincipal : ICPrincipal
testPrincipal = MkICPrincipal "2vxsx-fae"

testChain : ChainId
testChain = MkChainId 1

testTarget : EvmAddress
testTarget = MkEvmAddress "0x1234567890123456789012345678901234567890"

testNewImpl : EvmAddress
testNewImpl = MkEvmAddress "0xabcdef0123456789abcdef0123456789abcdef01"

testOU : EvmAddress
testOU = MkEvmAddress "0xfedcba9876543210fedcba9876543210fedcba98"

baseTime : Nat
baseTime = 1704067200000000000

-- =============================================================================
-- Full Pipeline Integration Tests
-- =============================================================================

||| INT_PIPE_001: Full proposal -> review -> execution pipeline
||| Tests the complete flow from LazyEvmLifecycle recommendation to execution
test_full_pipeline : IO Bool
test_full_pipeline = do
  let state0 = initialState testPrincipal

  -- Step 1: Receive proposal from LazyEvmLifecycle
  case receiveFromLifecycle state0 testChain testTarget testNewImpl testOU
         testPrincipal "Security upgrade" "0xcodehash" "lifecycle-evidence" baseTime of
    Fail f _ => do
      putStrLn $ "Failed to receive proposal: " ++ show f
      pure False
    Ok (state1, receipt) _ => do
      let pid = receipt.proposalId

      -- Step 2: Route to auditor
      let aid = MkAuditorId testPrincipal
      case routeToAuditor state1 pid aid (baseTime + 1000) of
        Fail f _ => do
          putStrLn $ "Failed to route: " ++ show f
          pure False
        Ok state2 _ => do

          -- Step 3: Process approval review
          case processReview state2 pid aid ApproveUpgrade "Approved after review" "sig123" (baseTime + 2000) of
            Fail f _ => do
              putStrLn $ "Failed to process review: " ++ show f
              pure False
            Ok state3 _ => do

              -- Step 4: Prepare execution
              case prepareExecution state3 pid (baseTime + 86400000000000) of
                Fail f _ => do
                  putStrLn $ "Failed to prepare execution: " ++ show f
                  pure False
                Ok execReq _ => do

                  -- Step 5: Record successful execution
                  case recordExecution state3 pid (ExecSuccess "0xtxhash123") (baseTime + 3000) of
                    Fail f _ => do
                      putStrLn $ "Failed to record execution: " ++ show f
                      pure False
                    Ok state4 _ => do
                      -- Verify final status
                      case findProposal state4 pid of
                        Fail _ _ => pure False
                        Ok finalProposal _ =>
                          pure (finalProposal.status == Executed)

||| INT_PIPE_002: Proposal rejection workflow
||| Tests the flow when auditor rejects proposal
test_rejection_workflow : IO Bool
test_rejection_workflow = do
  let state0 = initialState testPrincipal

  case receiveFromLifecycle state0 testChain testTarget testNewImpl testOU
         testPrincipal "Buggy upgrade" "0xbadcode" "lifecycle-evidence" baseTime of
    Fail _ _ => pure False
    Ok (state1, receipt) _ => do
      let pid = receipt.proposalId
          aid = MkAuditorId testPrincipal

      case routeToAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case processReview state2 pid aid (RejectUpgrade "Reentrancy vulnerability found") "Security issue" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case findProposal state3 pid of
                Fail _ _ => pure False
                Ok proposal _ => pure (proposal.status == Rejected)

-- =============================================================================
-- Edge Case Integration Tests
-- =============================================================================

||| INT_EDGE_001: Empty state handling
test_empty_state : IO Bool
test_empty_state = do
  let state = initialState testPrincipal

  -- Querying empty state should return appropriate results
  let pending = getPendingForChain state testChain
      awaiting = getAwaitingReview state
      approved = getApprovedForExecution state

  pure (null pending && null awaiting && null approved)

||| INT_EDGE_002: Invalid execution attempt on non-approved
test_invalid_execution : IO Bool
test_invalid_execution = do
  let state0 = initialState testPrincipal

  case submitProposal state0 testChain testTarget testNewImpl testOU
         testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      -- Try to prepare execution on Pending proposal
      case prepareExecution state1 pid (baseTime + 1000) of
        Fail (InvalidState _) _ => pure True  -- Expected failure
        Ok _ _ => pure False                   -- Should have failed
        Fail other _ => do
          putStrLn $ "Expected InvalidState but got " ++ show other
          pure False

-- =============================================================================
-- FRC Evidence Tests
-- =============================================================================

||| INT_EVID_001: Evidence chain preserved through operations
test_evidence_chain : IO Bool
test_evidence_chain = do
  let state0 = initialState testPrincipal

  case submitProposal state0 testChain testTarget testNewImpl testOU
         testPrincipal "Test" "0x1" baseTime of
    Ok (_, _) evidence =>
      -- Check evidence has required fields
      pure (evidence.phase == Update &&
            evidence.label == "submitProposal" &&
            not (null evidence.detail))
    Fail _ _ => pure False

-- =============================================================================
-- Test Collection
-- =============================================================================

record TestDef where
  constructor MkTestDef
  testId : String
  testName : String
  testFn : IO Bool

test : String -> String -> IO Bool -> TestDef
test = MkTestDef

public export
allTests : List TestDef
allTests =
  [ test "INT_PIPE_001" "Full proposal->execution pipeline" test_full_pipeline
  , test "INT_PIPE_002" "Proposal rejection workflow" test_rejection_workflow
  , test "INT_EDGE_001" "Empty state handling" test_empty_state
  , test "INT_EDGE_002" "Invalid execution attempt" test_invalid_execution
  , test "INT_EVID_001" "Evidence chain preserved" test_evidence_chain
  ]

-- =============================================================================
-- Test Runner
-- =============================================================================

runTestSuite : String -> List TestDef -> IO ()
runTestSuite suiteName tests = do
  putStrLn $ "=== " ++ suiteName ++ " Tests ==="
  results <- traverse runSingleTest tests
  let passed = length (filter id results)
      total = length results
  putStrLn $ "\nPassed: " ++ show passed ++ "/" ++ show total
  where
    runSingleTest : TestDef -> IO Bool
    runSingleTest t = do
      putStr $ t.testId ++ " " ++ t.testName ++ "... "
      result <- t.testFn
      putStrLn $ if result then "PASS" else "FAIL"
      pure result

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Run all tests
export
runAllTests : IO ()
runAllTests = runTestSuite "Integration" allTests

||| Main entry point
main : IO ()
main = runAllTests
