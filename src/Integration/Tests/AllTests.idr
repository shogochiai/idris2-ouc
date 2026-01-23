||| Integration Test Suite
||| These tests exercise full pipelines for OUC to maximize semantic coverage
module Integration.Tests.AllTests

import FRMonad.Core
import OUC.Functions.Core
import OUC.Types.Validated
import AuditorPool.Core
import AuditorPool.Tests.VoteTests
import Rewards.Core
import Proposals.Core
import Economics.Tests.FeeToCyclesE2E
import Economics.Tests.AllTests as EconTests
import Candid.Tests.AllTests as CandidTests
import Data.List
import Data.String

%default covering

-- =============================================================================
-- Test Infrastructure (local definitions to avoid LazyCore dependency)
-- =============================================================================

||| Test definition record
public export
record TestDef where
  constructor MkTestDef
  testId   : String
  testName : String
  testFn   : IO Bool

||| Create a test definition
public export
test : String -> String -> IO Bool -> Integration.Tests.AllTests.TestDef
test = Integration.Tests.AllTests.MkTestDef

runOne : Integration.Tests.AllTests.TestDef -> IO Bool
runOne t = do
  result <- t.testFn
  putStrLn $ (if result then "[PASS]" else "[FAIL]") ++ " " ++ t.testId ++ ": " ++ t.testName
  pure result

||| Run a test suite and report results
export
runTestSuite : String -> List Integration.Tests.AllTests.TestDef -> IO ()
runTestSuite suiteName tests = do
  putStrLn $ "Running " ++ suiteName ++ " tests..."
  results <- traverse runOne tests
  putStrLn $ "\n" ++ show (length (filter id results)) ++ "/" ++ show (length results) ++ " tests passed"

-- =============================================================================
-- Test Helpers
-- =============================================================================

testPrincipal : ValidatedPrincipal
testPrincipal = unsafeMkPrincipal "2vxsx-fae"

testChain : ChainId
testChain = MkChainId 1

testTarget : ValidatedEvmAddress
testTarget = unsafeMkEvmAddress "1234567890123456789012345678901234567890"

testNewImpl : ValidatedEvmAddress
testNewImpl = unsafeMkEvmAddress "abcdef0123456789abcdef0123456789abcdef01"

testOU : ValidatedEvmAddress
testOU = unsafeMkEvmAddress "fedcba9876543210fedcba9876543210fedcba98"

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
                          pure (finalProposal.state == SExecuted)

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
                Ok proposal _ => pure (proposal.state == SRejected)

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
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case markExecuted state3 pid "0xtxhash" baseTime of
                Ok state4 _ =>
                  case findProposal state4 pid of
                    Ok p _ => pure (p.state == SExecuted)
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "looks good" "sig" baseTime of
            Ok state3 _ =>
              case findProposal state3 pid of
                Ok p _ => pure (p.state == SApproved)
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
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid (RequestChanges "add tests") "needs work" "sig" baseTime of
            Ok state3 _ =>
              case findProposal state3 pid of
                Ok p _ => pure (p.state == SUnderReview)
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
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
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              let awaiting = getAwaitingReview state3
              in pure (null awaiting)

-- =============================================================================
-- AuditorPool Tests (HIGH IMPACT - previously untested)
-- =============================================================================

testAuditorPrincipal : ValidatedPrincipal
testAuditorPrincipal = unsafeMkPrincipal "aaaaa-aa"

testAuditorPrincipal2 : ValidatedPrincipal
testAuditorPrincipal2 = unsafeMkPrincipal "bbbbb-bb"

testPoolConfig : PoolConfig
testPoolConfig = defaultConfig

||| INT_POOL_001: registerAuditor with sufficient stake succeeds
test_registerAuditor_success : IO Bool
test_registerAuditor_success = do
  case registerAuditor [] testAuditorPrincipal 1500 baseTime testPoolConfig of
    Ok (auditors, aid) _ =>
      pure (length auditors == 1 && aid == MkAuditorId testAuditorPrincipal)
    Fail _ _ => pure False

||| INT_POOL_002: registerAuditor with insufficient stake fails
test_registerAuditor_insufficientStake : IO Bool
test_registerAuditor_insufficientStake = do
  case registerAuditor [] testAuditorPrincipal 500 baseTime testPoolConfig of
    Fail (Unauthorized _) _ => pure True
    _ => pure False

||| INT_POOL_003: registerAuditor duplicate fails
test_registerAuditor_duplicate : IO Bool
test_registerAuditor_duplicate = do
  case registerAuditor [] testAuditorPrincipal 1500 baseTime testPoolConfig of
    Fail _ _ => pure False
    Ok (auditors, _) _ =>
      case registerAuditor auditors testAuditorPrincipal 1500 baseTime testPoolConfig of
        Fail (Conflict _) _ => pure True
        _ => pure False

||| INT_POOL_004: selectAuditor ByReputation
test_selectAuditor_byReputation : IO Bool
test_selectAuditor_byReputation = do
  let auditor1 = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1500 baseTime
  let auditor2 = MkAuditor (MkAuditorId testAuditorPrincipal2) Active 800 0 0 0 0 1500 baseTime
  case selectAuditor [auditor1, auditor2] ByReputation testPoolConfig of
    Ok selectedId _ => pure (selectedId == MkAuditorId testAuditorPrincipal2)
    Fail _ _ => pure False

||| INT_POOL_005: selectAuditor ByAvailability
test_selectAuditor_byAvailability : IO Bool
test_selectAuditor_byAvailability = do
  let auditor1 = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 10 0 0 0 1500 baseTime
  let auditor2 = MkAuditor (MkAuditorId testAuditorPrincipal2) Active 600 2 0 0 0 1500 baseTime
  case selectAuditor [auditor1, auditor2] ByAvailability testPoolConfig of
    Ok selectedId _ => pure (selectedId == MkAuditorId testAuditorPrincipal2)
    Fail _ _ => pure False

||| INT_POOL_006: selectAuditor with no active auditors fails
test_selectAuditor_noAuditors : IO Bool
test_selectAuditor_noAuditors = do
  case selectAuditor [] ByReputation testPoolConfig of
    Fail (NotFound _) _ => pure True
    _ => pure False

||| INT_POOL_007: selectAuditor Weighted
test_selectAuditor_weighted : IO Bool
test_selectAuditor_weighted = do
  let auditor1 = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1000 baseTime
  let auditor2 = MkAuditor (MkAuditorId testAuditorPrincipal2) Active 700 0 0 0 0 2000 baseTime
  case selectAuditor [auditor1, auditor2] Weighted testPoolConfig of
    Ok selectedId _ => pure (selectedId == MkAuditorId testAuditorPrincipal2)
    Fail _ _ => pure False

||| INT_POOL_008: slashAuditor success
test_slashAuditor_success : IO Bool
test_slashAuditor_success = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1000 baseTime
  case slashAuditor [auditor] (MkAuditorId testAuditorPrincipal) "misbehavior" testPoolConfig of
    Ok (auditors, slashedAmount) _ =>
      case auditors of
        [a] => pure (a.status == Slashed && slashedAmount == 100)
        _ => pure False
    Fail _ _ => pure False

||| INT_POOL_009: slashAuditor not found
test_slashAuditor_notFound : IO Bool
test_slashAuditor_notFound = do
  case slashAuditor [] (MkAuditorId testAuditorPrincipal) "reason" testPoolConfig of
    Fail (NotFound _) _ => pure True
    _ => pure False

||| INT_POOL_010: suspendAuditor success
test_suspendAuditor_success : IO Bool
test_suspendAuditor_success = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1000 baseTime
  case suspendAuditor [auditor] (MkAuditorId testAuditorPrincipal) "violation" of
    Ok auditors _ =>
      case auditors of
        [a] => pure (a.status == Suspended)
        _ => pure False
    Fail _ _ => pure False

||| INT_POOL_011: reactivateAuditor from Suspended
test_reactivateAuditor_suspended : IO Bool
test_reactivateAuditor_suspended = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Suspended 600 0 0 0 0 1000 baseTime
  case reactivateAuditor [auditor] (MkAuditorId testAuditorPrincipal) of
    Ok auditors _ =>
      case auditors of
        [a] => pure (a.status == Active)
        _ => pure False
    Fail _ _ => pure False

||| INT_POOL_012: reactivateAuditor from Slashed fails
test_reactivateAuditor_slashed : IO Bool
test_reactivateAuditor_slashed = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Slashed 600 0 0 0 1 500 baseTime
  case reactivateAuditor [auditor] (MkAuditorId testAuditorPrincipal) of
    Fail (InvalidState _) _ => pure True
    _ => pure False

||| INT_POOL_013: updateReputation positive delta
test_updateReputation_positive : IO Bool
test_updateReputation_positive = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1000 baseTime
  case updateReputation [auditor] (MkAuditorId testAuditorPrincipal) 50 of
    Ok auditors _ =>
      case auditors of
        [a] => pure (a.reputation == 650)
        _ => pure False
    Fail _ _ => pure False

||| INT_POOL_014: updateReputation negative delta
test_updateReputation_negative : IO Bool
test_updateReputation_negative = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Active 600 0 0 0 0 1000 baseTime
  case updateReputation [auditor] (MkAuditorId testAuditorPrincipal) (-100) of
    Ok auditors _ =>
      case auditors of
        [a] => pure (a.reputation == 500)
        _ => pure False
    Fail _ _ => pure False

||| INT_POOL_015: updateReputation caps at 1000
test_updateReputation_cap : IO Bool
test_updateReputation_cap = do
  let auditor = MkAuditor (MkAuditorId testAuditorPrincipal) Active 950 0 0 0 0 1000 baseTime
  case updateReputation [auditor] (MkAuditorId testAuditorPrincipal) 100 of
    Ok auditors _ =>
      case auditors of
        [a] => pure (a.reputation == 1000)
        _ => pure False
    Fail _ _ => pure False

-- =============================================================================
-- Rewards.Core Tests (HIGH IMPACT - previously untested)
-- =============================================================================

testRewardsConfig : RewardsConfig
testRewardsConfig = defaultRewardsConfig

||| INT_RWD_001: collectFee with sufficient amount succeeds
test_collectFee_success : IO Bool
test_collectFee_success = do
  let state0 = initialRewardsState testRewardsConfig
      pid = MkProposalId 1
  case collectFee state0 pid testPrincipal 100 baseTime of
    Ok state1 _ =>
      pure (length state1.fees == 1 && state1.treasury.totalCollected == 100)
    Fail _ _ => pure False

||| INT_RWD_002: collectFee with insufficient amount fails
test_collectFee_insufficient : IO Bool
test_collectFee_insufficient = do
  let state0 = initialRewardsState testRewardsConfig
      pid = MkProposalId 1
  case collectFee state0 pid testPrincipal 50 baseTime of
    Fail (Unauthorized _) _ => pure True
    _ => pure False

||| INT_RWD_003: queueReward with existing fee succeeds
test_queueReward_success : IO Bool
test_queueReward_success = do
  let state0 = initialRewardsState testRewardsConfig
      pid = MkProposalId 1
      aid = MkAuditorId testPrincipal
  case collectFee state0 pid testPrincipal 100 baseTime of
    Fail _ _ => pure False
    Ok state1 _ =>
      case queueReward state1 aid pid True True of
        Ok state2 _ => pure (length state2.pendingRewards == 1)
        Fail _ _ => pure False

||| INT_RWD_004: queueReward without fee fails
test_queueReward_noFee : IO Bool
test_queueReward_noFee = do
  let state0 = initialRewardsState testRewardsConfig
      pid = MkProposalId 99
      aid = MkAuditorId testPrincipal
  case queueReward state0 aid pid False False of
    Fail (NotFound _) _ => pure True
    _ => pure False

||| INT_RWD_005: distributeReward with pending reward succeeds
||| Note: With default config, 80% goes to auditor, 20% to treasury
||| Treasury must have enough to pay reward. Collect multiple fees first.
test_distributeReward_success : IO Bool
test_distributeReward_success = do
  let state0 = initialRewardsState testRewardsConfig
      pid1 = MkProposalId 1
      pid2 = MkProposalId 2
      pid3 = MkProposalId 3
      pid4 = MkProposalId 4
      pid5 = MkProposalId 5
      aid = MkAuditorId testPrincipal
  -- Collect 5 fees (500 each) to build up treasury: 5 * 500 * 20% = 500
  case collectFee state0 pid1 testPrincipal 500 baseTime of
    Fail _ _ => pure False
    Ok state1 _ =>
      case collectFee state1 pid2 testPrincipal 500 baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case collectFee state2 pid3 testPrincipal 500 baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              case collectFee state3 pid4 testPrincipal 500 baseTime of
                Fail _ _ => pure False
                Ok state4 _ =>
                  case collectFee state4 pid5 testPrincipal 500 baseTime of
                    Fail _ _ => pure False
                    Ok state5 _ =>
                      -- Now treasury has 500. Queue reward for pid1 (400 = 80% of 500)
                      case queueReward state5 aid pid1 False False of
                        Fail _ _ => pure False
                        Ok state6 _ =>
                          case distributeReward state6 aid pid1 "0xtxhash" (baseTime + 1000) of
                            Ok (state7, amount) _ =>
                              pure (length state7.distributions == 1 && length state7.pendingRewards == 0)
                            Fail _ _ => pure False

||| INT_RWD_006: distributeReward with no pending fails
test_distributeReward_noPending : IO Bool
test_distributeReward_noPending = do
  let state0 = initialRewardsState testRewardsConfig
      aid = MkAuditorId testPrincipal
      pid = MkProposalId 99
  case distributeReward state0 aid pid "0xtx" baseTime of
    Fail (NotFound _) _ => pure True
    _ => pure False

||| INT_RWD_007: getPendingReward returns correct sum
test_getPendingReward : IO Bool
test_getPendingReward = do
  let state0 = initialRewardsState testRewardsConfig
      pid1 = MkProposalId 1
      pid2 = MkProposalId 2
      aid = MkAuditorId testPrincipal
  case collectFee state0 pid1 testPrincipal 100 baseTime of
    Fail _ _ => pure False
    Ok state1 _ =>
      case collectFee state1 pid2 testPrincipal 100 baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case queueReward state2 aid pid1 False False of
            Fail _ _ => pure False
            Ok state3 _ =>
              case queueReward state3 aid pid2 False False of
                Fail _ _ => pure False
                Ok state4 _ =>
                  case getPendingReward state4 aid of
                    Ok pendingTotal _ => pure (pendingTotal > 0)
                    Fail _ _ => pure False

||| INT_RWD_008: getTreasuryBalance returns correct value
test_getTreasuryBalance : IO Bool
test_getTreasuryBalance = do
  let state0 = initialRewardsState testRewardsConfig
      pid = MkProposalId 1
  case collectFee state0 pid testPrincipal 100 baseTime of
    Fail _ _ => pure False
    Ok state1 _ =>
      case getTreasuryBalance state1 of
        Ok balance _ => pure (balance == 20)  -- 20% treasury share
        Fail _ _ => pure False

||| INT_RWD_009: calculateReward with bonuses
test_calculateReward_bonuses : IO Bool
test_calculateReward_bonuses = do
  let config = testRewardsConfig
      baseReward = calculateReward config 100 False False
      withQuality = calculateReward config 100 True False
      withSpeed = calculateReward config 100 False True
      withBoth = calculateReward config 100 True True
  pure (withQuality > baseReward &&
        withSpeed > baseReward &&
        withBoth > withQuality &&
        withBoth > withSpeed)

-- =============================================================================
-- Proposals.Core Tests (validateProposal, countByStatus)
-- =============================================================================

testChainConfig : ChainConfig
testChainConfig = MkChainConfig testChain testOU testTarget "https://rpc.example.com" True

testInactiveChainConfig : ChainConfig
testInactiveChainConfig = MkChainConfig (MkChainId 137) testOU testTarget "https://rpc.polygon.com" False

||| INT_VAL_001: validateProposal with valid chain succeeds
test_validateProposal_valid : IO Bool
test_validateProposal_valid = do
  let state0 = initialState testPrincipal
      expiresAt = baseTime + 86400000000000
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      case findProposal state1 pid of
        Fail _ _ => pure False
        Ok proposal _ =>
          case validateProposal proposal [testChainConfig] baseTime of
            Ok Valid _ => pure True
            Ok other _ => do
              putStrLn $ "Expected Valid but got " ++ show other
              pure False
            Fail _ _ => pure False

||| INT_VAL_002: validateProposal with unknown chain fails
test_validateProposal_unknownChain : IO Bool
test_validateProposal_unknownChain = do
  let state0 = initialState testPrincipal
      unknownChain = MkChainId 999
  case submitProposal state0 unknownChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      case findProposal state1 pid of
        Fail _ _ => pure False
        Ok proposal _ =>
          case validateProposal proposal [testChainConfig] baseTime of
            Ok (InvalidChain _) _ => pure True
            _ => pure False

||| INT_VAL_003: validateProposal with inactive chain fails
test_validateProposal_inactiveChain : IO Bool
test_validateProposal_inactiveChain = do
  let state0 = initialState testPrincipal
      inactiveChain = MkChainId 137
  case submitProposal state0 inactiveChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      case findProposal state1 pid of
        Fail _ _ => pure False
        Ok proposal _ =>
          case validateProposal proposal [testInactiveChainConfig] baseTime of
            Ok (InvalidChain _) _ => pure True
            _ => pure False

||| INT_VAL_004: validateProposal with expired proposal
||| Note: Proposal expiresAt is set to now + 604800000000000 (7 days in nanoseconds)
test_validateProposal_expired : IO Bool
test_validateProposal_expired = do
  let state0 = initialState testPrincipal
      futureTime = baseTime + 700000000000000  -- More than 7 days later
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      case findProposal state1 pid of
        Fail _ _ => pure False
        Ok proposal _ =>
          case validateProposal proposal [testChainConfig] futureTime of
            Ok ExpiredProposal _ => pure True
            _ => pure False

||| INT_CNT_001: countByStatus with Pending
test_countByStatus_pending : IO Bool
test_countByStatus_pending = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test1" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, _) _ =>
      case submitProposal state1 testChain testTarget testNewImpl testOU testPrincipal "Test2" "0x2" baseTime of
        Fail _ _ => pure False
        Ok (state2, _) _ =>
          pure (countByState state2 SPending == 2)

||| INT_CNT_002: countByStatus with UnderReview
test_countByStatus_underReview : IO Bool
test_countByStatus_underReview = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          pure (countByState state2 SUnderReview == 1 && countByState state2 SPending == 0)

||| INT_CNT_003: countByStatus with Approved
test_countByStatus_approved : IO Bool
test_countByStatus_approved = do
  let state0 = initialState testPrincipal
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" baseTime of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      let aid = MkAuditorId testPrincipal
      in case assignAuditorToProposal state1 pid aid baseTime of
        Fail _ _ => pure False
        Ok state2 _ =>
          case submitReview state2 pid aid ApproveUpgrade "ok" "sig" baseTime of
            Fail _ _ => pure False
            Ok state3 _ =>
              pure (countByState state3 SApproved == 1)

||| INT_CNT_004: countByStatus with empty state
test_countByStatus_empty : IO Bool
test_countByStatus_empty = do
  let state = initialState testPrincipal
  pure (countByState state SPending == 0 &&
        countByState state SUnderReview == 0 &&
        countByState state SApproved == 0 &&
        countByState state SRejected == 0 &&
        countByState state SExecuted == 0)

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
allTests : List Integration.Tests.AllTests.TestDef
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
  -- AuditorPool tests (HIGH IMPACT - previously untested)
  , test "REQ_INT_POOL_001" "registerAuditor success" test_registerAuditor_success
  , test "REQ_INT_POOL_002" "registerAuditor insufficient stake" test_registerAuditor_insufficientStake
  , test "REQ_INT_POOL_003" "registerAuditor duplicate" test_registerAuditor_duplicate
  , test "REQ_INT_POOL_004" "selectAuditor ByReputation" test_selectAuditor_byReputation
  , test "REQ_INT_POOL_005" "selectAuditor ByAvailability" test_selectAuditor_byAvailability
  , test "REQ_INT_POOL_006" "selectAuditor no auditors" test_selectAuditor_noAuditors
  , test "REQ_INT_POOL_007" "selectAuditor Weighted" test_selectAuditor_weighted
  , test "REQ_INT_POOL_008" "slashAuditor success" test_slashAuditor_success
  , test "REQ_INT_POOL_009" "slashAuditor not found" test_slashAuditor_notFound
  , test "REQ_INT_POOL_010" "suspendAuditor success" test_suspendAuditor_success
  , test "REQ_INT_POOL_011" "reactivateAuditor from Suspended" test_reactivateAuditor_suspended
  , test "REQ_INT_POOL_012" "reactivateAuditor from Slashed" test_reactivateAuditor_slashed
  , test "REQ_INT_POOL_013" "updateReputation positive" test_updateReputation_positive
  , test "REQ_INT_POOL_014" "updateReputation negative" test_updateReputation_negative
  , test "REQ_INT_POOL_015" "updateReputation cap" test_updateReputation_cap
  -- Rewards.Core tests (HIGH IMPACT - previously untested)
  , test "REQ_INT_RWD_001" "collectFee success" test_collectFee_success
  , test "REQ_INT_RWD_002" "collectFee insufficient" test_collectFee_insufficient
  , test "REQ_INT_RWD_003" "queueReward success" test_queueReward_success
  , test "REQ_INT_RWD_004" "queueReward no fee" test_queueReward_noFee
  , test "REQ_INT_RWD_005" "distributeReward success" test_distributeReward_success
  , test "REQ_INT_RWD_006" "distributeReward no pending" test_distributeReward_noPending
  , test "REQ_INT_RWD_007" "getPendingReward sum" test_getPendingReward
  , test "REQ_INT_RWD_008" "getTreasuryBalance" test_getTreasuryBalance
  , test "REQ_INT_RWD_009" "calculateReward bonuses" test_calculateReward_bonuses
  -- Proposals.Core tests (validateProposal, countByStatus)
  , test "REQ_INT_VAL_001" "validateProposal valid" test_validateProposal_valid
  , test "REQ_INT_VAL_002" "validateProposal unknown chain" test_validateProposal_unknownChain
  , test "REQ_INT_VAL_003" "validateProposal inactive chain" test_validateProposal_inactiveChain
  , test "REQ_INT_VAL_004" "validateProposal expired" test_validateProposal_expired
  , test "REQ_INT_CNT_001" "countByStatus Pending" test_countByStatus_pending
  , test "REQ_INT_CNT_002" "countByStatus UnderReview" test_countByStatus_underReview
  , test "REQ_INT_CNT_003" "countByStatus Approved" test_countByStatus_approved
  , test "REQ_INT_CNT_004" "countByStatus empty" test_countByStatus_empty
  ]

-- =============================================================================
-- Main Entry Point
-- =============================================================================

-- E2E tests converted to TestDef format
e2eToTestDef : Economics.Tests.FeeToCyclesE2E.TestResult -> Integration.Tests.AllTests.TestDef
e2eToTestDef r = Integration.Tests.AllTests.MkTestDef r.testId r.testName (pure r.passed)

e2eTestDefs : List Integration.Tests.AllTests.TestDef
e2eTestDefs = map e2eToTestDef allE2ETests

-- Convert vote tests tuple format to TestDef
voteToTestDef : (String, String, IO Bool) -> Integration.Tests.AllTests.TestDef
voteToTestDef (id, name, fn) = Integration.Tests.AllTests.MkTestDef id name fn

voteTestDefs : List Integration.Tests.AllTests.TestDef
voteTestDefs = map voteToTestDef voteTests

||| Run all tests (required by idris2-coverage UnifiedRunner)
export
runAllTests : IO ()
runAllTests = do
  Integration.Tests.AllTests.runTestSuite "Integration" Integration.Tests.AllTests.allTests
  Integration.Tests.AllTests.runTestSuite "Fee-to-Cycles E2E" e2eTestDefs
  Integration.Tests.AllTests.runTestSuite "Vote (n-of-m threshold)" voteTestDefs
  EconTests.runAllTests
  CandidTests.runExtendedTests

||| Main entry point
main : IO ()
main = Integration.Tests.AllTests.runAllTests
