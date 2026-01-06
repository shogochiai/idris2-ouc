||| Integration Test Suite
||| These tests exercise full pipelines for OUC to maximize semantic coverage
module Integration.Tests.AllTests

import Idris2CoverageHelper.PerModule
import FRMonad.Core
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
-- markExecuted Case Block Tests (severity=Inf)
-- =============================================================================

||| INT_EXEC_001: markExecuted on approved proposal succeeds
test_markExecuted_approved : IO Bool
test_markExecuted_approved = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case markExecuted state3 pid "0xtxhash" baseTime of
                Ok state4 _ =>
                  case findProposal state4 pid of
                    Ok p _ => pure (p.status == Executed)
                    Fail _ _ => pure False
                Fail _ _ => pure False

||| INT_EXEC_002: markExecuted on pending proposal fails with InvalidState
test_markExecuted_pending : IO Bool
test_markExecuted_pending = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      case markExecuted state1 pid "0xtxhash" baseTime of
        Fail (InvalidState _) _ => pure True
        _ => pure False

||| INT_EXEC_003: markExecuted on rejected proposal fails
test_markExecuted_rejected : IO Bool
test_markExecuted_rejected = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid (RejectUpgrade "bad") "no" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case markExecuted state3 pid "0xtxhash" baseTime of
                Fail (InvalidState _) _ => pure True
                _ => pure False

-- =============================================================================
-- submitReview Case Block Tests (severity=Inf)
-- =============================================================================

||| INT_REV_001: submitReview on UnderReview proposal succeeds
test_submitReview_underReview : IO Bool
test_submitReview_underReview = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "looks good" "sig" baseTime of
            Ok state3 _ =>
              case findProposal state3 pid of
                Ok p _ => pure (p.status == Approved)
                Fail _ _ => pure False
            Fail _ _ => pure False

||| INT_REV_002: submitReview on pending proposal fails
test_submitReview_pending : IO Bool
test_submitReview_pending = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case submitReview state1 pid aid ApproveUpgrade "nope" "sig" baseTime of
        Fail (InvalidState _) _ => pure True
        _ => pure False

||| INT_REV_003: submitReview with RequestChanges keeps UnderReview status
test_submitReview_requestChanges : IO Bool
test_submitReview_requestChanges = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid (RequestChanges "add tests") "needs work" "sig" baseTime of
            Ok state3 _ =>
              case findProposal state3 pid of
                Ok p _ => pure (p.status == UnderReview)
                Fail _ _ => pure False
            Fail _ _ => pure False

-- =============================================================================
-- getPendingForChain Tests (severity=5.0)
-- =============================================================================

||| INT_PEND_001: getPendingForChain with matching chain
test_getPendingForChain_match : IO Bool
test_getPendingForChain_match = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let pending = getPendingForChain state1 testChain
      in pure (length pending == 1)

||| INT_PEND_002: getPendingForChain with non-matching chain
test_getPendingForChain_noMatch : IO Bool
test_getPendingForChain_noMatch = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, _) _ =>
      let otherChain = MkChainId 137
          pending = getPendingForChain state1 otherChain
      in pure (null pending)

||| INT_PEND_003: getPendingForChain excludes non-Pending status
test_getPendingForChain_excludeNonPending : IO Bool
test_getPendingForChain_excludeNonPending = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          let pending = getPendingForChain state2 testChain
          in pure (null pending)

||| INT_PEND_004: getPendingForChain with multiple proposals
test_getPendingForChain_multiple : IO Bool
test_getPendingForChain_multiple = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test1" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, _) _ =>
      case submitProposal state1 testChain testTarget testNewImpl testOU testPrincipal "Test2" "0x2" baseTime of
        Fail _ _ => pure False
        Ok (state2, _) _ =>
          let pending = getPendingForChain state2 testChain
          in pure (length pending == 2)

-- =============================================================================
-- recordExecution Tests (severity=4.0)
-- =============================================================================

||| INT_RECEX_001: recordExecution with ExecReverted
test_recordExecution_reverted : IO Bool
test_recordExecution_reverted = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case recordExecution state3 pid (ExecReverted "out of gas") baseTime of
                Fail (CallError _) _ => pure True
                _ => pure False

||| INT_RECEX_002: recordExecution with ExecTimeout
test_recordExecution_timeout : IO Bool
test_recordExecution_timeout = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case recordExecution state3 pid ExecTimeout baseTime of
                Fail (Timeout _) _ => pure True
                _ => pure False

||| INT_RECEX_003: recordExecution with ExecRpcError
test_recordExecution_rpcError : IO Bool
test_recordExecution_rpcError = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case recordExecution state3 pid (ExecRpcError (-32000) "nonce too low") baseTime of
                Fail (CallError _) _ => pure True
                _ => pure False

-- =============================================================================
-- getAwaitingReview Tests (severity=2.0)
-- =============================================================================

||| INT_AWAIT_001: getAwaitingReview with UnderReview proposals
test_getAwaitingReview_present : IO Bool
test_getAwaitingReview_present = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          let awaiting = getAwaitingReview state2
          in pure (length awaiting == 1)

||| INT_AWAIT_002: getAwaitingReview excludes Approved
test_getAwaitingReview_excludeApproved : IO Bool
test_getAwaitingReview_excludeApproved = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditor state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              let awaiting = getAwaitingReview state3
              in pure (null awaiting)

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

public export
allTests : List TestDef
allTests =
  [ test "REQ_INT_PIPE_001" "Full proposal->execution pipeline" test_full_pipeline
  , test "REQ_INT_PIPE_002" "Proposal rejection workflow" test_rejection_workflow
  , test "REQ_INT_EDGE_001" "Empty state handling" test_empty_state
  , test "REQ_INT_EDGE_002" "Invalid execution attempt" test_invalid_execution
  , test "REQ_INT_EVID_001" "Evidence chain preserved" test_evidence_chain
  -- markExecuted case block tests (severity=Inf)
  , test "REQ_INT_EXEC_001" "markExecuted on approved" test_markExecuted_approved
  , test "REQ_INT_EXEC_002" "markExecuted on pending fails" test_markExecuted_pending
  , test "REQ_INT_EXEC_003" "markExecuted on rejected fails" test_markExecuted_rejected
  -- submitReview case block tests (severity=Inf)
  , test "REQ_INT_REV_001" "submitReview on UnderReview" test_submitReview_underReview
  , test "REQ_INT_REV_002" "submitReview on pending fails" test_submitReview_pending
  , test "REQ_INT_REV_003" "submitReview RequestChanges" test_submitReview_requestChanges
  -- getPendingForChain tests (severity=5.0)
  , test "REQ_INT_PEND_001" "getPendingForChain match" test_getPendingForChain_match
  , test "REQ_INT_PEND_002" "getPendingForChain no match" test_getPendingForChain_noMatch
  , test "REQ_INT_PEND_003" "getPendingForChain excludes non-Pending" test_getPendingForChain_excludeNonPending
  , test "REQ_INT_PEND_004" "getPendingForChain multiple" test_getPendingForChain_multiple
  -- recordExecution tests (severity=4.0)
  , test "REQ_INT_RECEX_001" "recordExecution reverted" test_recordExecution_reverted
  , test "REQ_INT_RECEX_002" "recordExecution timeout" test_recordExecution_timeout
  , test "REQ_INT_RECEX_003" "recordExecution RPC error" test_recordExecution_rpcError
  -- getAwaitingReview tests (severity=2.0)
  , test "REQ_INT_AWAIT_001" "getAwaitingReview present" test_getAwaitingReview_present
  , test "REQ_INT_AWAIT_002" "getAwaitingReview excludes Approved" test_getAwaitingReview_excludeApproved
  ]

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Run all tests (required by idris2-coverage UnifiedRunner)
export
runAllTests : IO ()
runAllTests = runTestSuite "Integration" allTests

||| Main entry point
main : IO ()
main = runAllTests
