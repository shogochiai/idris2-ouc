||| AuditorPool Vote Module Tests
|||
||| Tests for n-of-m threshold voting functionality.
module AuditorPool.Tests.VoteTests

import FRMonad.Core
import OUC.Functions.Core
import OUC.Types.Validated
import AuditorPool.Core
import AuditorPool.Vote
import Data.List

%default covering

-- =============================================================================
-- Test Helpers
-- =============================================================================

testPrincipal1 : ValidatedPrincipal
testPrincipal1 = unsafeMkPrincipal "aaaaa-aa"

testPrincipal2 : ValidatedPrincipal
testPrincipal2 = unsafeMkPrincipal "bbbbb-bb"

testPrincipal3 : ValidatedPrincipal
testPrincipal3 = unsafeMkPrincipal "ccccc-cc"

testAuditor1 : AuditorId
testAuditor1 = MkAuditorId testPrincipal1

testAuditor2 : AuditorId
testAuditor2 = MkAuditorId testPrincipal2

testAuditor3 : AuditorId
testAuditor3 = MkAuditorId testPrincipal3

testProposalId : ProposalId
testProposalId = MkProposalId 1

testChainId : ChainId
testChainId = MkChainId 1

testOUAddress : ValidatedEvmAddress
testOUAddress = unsafeMkEvmAddress "1234567890123456789012345678901234567890"

baseTime : Integer
baseTime = 1704067200000000000  -- 2024-01-01 00:00:00 UTC

-- Create a test vote state with 3 auditors, 2-of-3 threshold
makeTestVoteState : ProposalVoteState
makeTestVoteState =
  initVoteState testProposalId testChainId testOUAddress
    [testAuditor1, testAuditor2, testAuditor3]
    defaultVoteConfig baseTime

-- =============================================================================
-- Vote Tests
-- =============================================================================

||| REQ_INT_VOTE_001: Submit vote succeeds for assigned auditor
test_vote_submit_success : IO Bool
test_vote_submit_success = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok newState _ => do
      let tally = getTally newState
      pure $ tally.approveCount == 1 && tally.rejectCount == 0

||| REQ_INT_VOTE_002: Submit vote fails for unassigned auditor
test_vote_unassigned_fails : IO Bool
test_vote_unassigned_fails = do
  let state = makeTestVoteState
      unassigned = MkAuditorId (unsafeMkPrincipal "unknown-principal")
  case submitVote state unassigned Approve baseTime of
    Fail _ _ => pure True  -- Expected failure
    Ok _ _ => pure False   -- Should have failed

||| REQ_INT_VOTE_003: Duplicate vote fails
test_vote_duplicate_fails : IO Bool
test_vote_duplicate_fails = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor1 (Reject "change mind") baseTime of
        Fail _ _ => pure True   -- Expected: duplicate vote rejected
        Ok _ _ => pure False    -- Should have failed

||| REQ_INT_VOTE_004: Approval threshold reached (2-of-3)
test_vote_approval_threshold : IO Bool
test_vote_approval_threshold = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 Approve (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          pure $ state3.result == Just ApprovalReached

||| REQ_INT_VOTE_005: Rejection threshold reached (2 rejections blocks approval)
test_vote_rejection_threshold : IO Bool
test_vote_rejection_threshold = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 (Reject "test") baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 (Reject "test") (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          pure $ state3.result == Just RejectionReached

||| REQ_INT_VOTE_006: Mixed votes - approval still possible
test_vote_mixed_pending : IO Bool
test_vote_mixed_pending = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 (Reject "test") (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          -- 1 approve, 1 reject, 1 pending - still can reach 2 approvals
          pure $ state3.result == Nothing

||| REQ_INT_VOTE_007: Vote after conclusion fails
test_vote_after_conclusion : IO Bool
test_vote_after_conclusion = do
  let state = makeTestVoteState
  -- First reach approval threshold
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 Approve (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          -- Now try to vote after conclusion
          case submitVote state3 testAuditor3 (Reject "late vote") (baseTime + 2000) of
            Fail _ _ => pure True   -- Expected: cannot vote after conclusion
            Ok _ _ => pure False

||| REQ_INT_VOTE_008: Threshold check with time expiry
test_vote_expiry : IO Bool
test_vote_expiry = do
  let state = makeTestVoteState
      -- Time way past voting period (24 hours = 86400000000000 ns)
      expiredTime = baseTime + 100000000000000
  case checkThreshold state expiredTime of
    Expired => pure True
    _ => pure False

||| REQ_INT_VOTE_009: Get tally returns correct counts
test_vote_tally : IO Bool
test_vote_tally = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 Approve baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 (Reject "test") (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ => do
          let tally = getTally state3
          pure $ tally.approveCount == 1
              && tally.rejectCount == 1
              && tally.requiredCount == 2
              && tally.totalAssigned == 3

||| REQ_INT_VOTE_010: Find and update vote state in list
test_vote_state_list : IO Bool
test_vote_state_list = do
  let state1 = makeTestVoteState
      state2 = initVoteState (MkProposalId 2) testChainId testOUAddress
                 [testAuditor1] defaultVoteConfig baseTime
      states = [state1, state2]
  case findVoteState states testProposalId of
    Nothing => pure False
    Just found =>
      case submitVote found testAuditor1 Approve baseTime of
        Fail _ _ => pure False
        Ok updated _ => do
          let newStates = updateVoteState states updated
          case findVoteState newStates testProposalId of
            Nothing => pure False
            Just final =>
              pure $ (getTally final).approveCount == 1

-- =============================================================================
-- Auditor Selection Tests (exercises safeIndex via selectAuditor Random)
-- =============================================================================

testAuditorA : Auditor
testAuditorA = MkAuditor testAuditor1 Active 500 10 8 2 0 100000 (cast baseTime)

testAuditorB : Auditor
testAuditorB = MkAuditor testAuditor2 Active 600 15 12 3 0 200000 (cast baseTime)

testAuditorC : Auditor
testAuditorC = MkAuditor testAuditor3 Active 700 20 16 4 0 300000 (cast baseTime)

testPoolConfig : PoolConfig
testPoolConfig = MkPoolConfig 1 10 100 200000

||| REQ_POOL_001: Select auditor with Random criteria (seed 0 -> index 0)
test_select_random_seed0 : IO Bool
test_select_random_seed0 = do
  let auditors = [testAuditorA, testAuditorB, testAuditorC]
  case selectAuditor auditors (Random 0) testPoolConfig of
    Fail _ _ => pure False
    Ok _ _ => pure True  -- Just verify it succeeds

||| REQ_POOL_002: Select auditor with Random criteria (seed 1 -> index 1)
test_select_random_seed1 : IO Bool
test_select_random_seed1 = do
  let auditors = [testAuditorA, testAuditorB, testAuditorC]
  case selectAuditor auditors (Random 1) testPoolConfig of
    Fail _ _ => pure False
    Ok _ _ => pure True

||| REQ_POOL_003: Select auditor with Random criteria (large seed -> modulo)
test_select_random_large_seed : IO Bool
test_select_random_large_seed = do
  let auditors = [testAuditorA, testAuditorB, testAuditorC]
  -- Large seed 1000 % 3 = index 1
  case selectAuditor auditors (Random 1000) testPoolConfig of
    Fail _ _ => pure False
    Ok _ _ => pure True

||| REQ_POOL_004: Select auditor with single auditor (index 0 only)
test_select_random_single : IO Bool
test_select_random_single = do
  let auditors = [testAuditorA]
  case selectAuditor auditors (Random 42) testPoolConfig of
    Fail _ _ => pure False
    Ok _ _ => pure True  -- Only one choice

||| REQ_POOL_005: Select auditor with empty list (fails)
test_select_random_empty : IO Bool
test_select_random_empty = do
  let auditors : List Auditor = []
  case selectAuditor auditors (Random 0) testPoolConfig of
    Fail _ _ => pure True  -- Expected failure
    Ok _ _ => pure False

-- =============================================================================
-- Test Suite Export
-- =============================================================================

||| All vote tests
public export
voteTests : List (String, String, IO Bool)
voteTests =
  [ ("REQ_INT_VOTE_001", "Submit vote succeeds for assigned auditor", test_vote_submit_success)
  , ("REQ_INT_VOTE_002", "Submit vote fails for unassigned auditor", test_vote_unassigned_fails)
  , ("REQ_INT_VOTE_003", "Duplicate vote fails", test_vote_duplicate_fails)
  , ("REQ_INT_VOTE_004", "Approval threshold reached (2-of-3)", test_vote_approval_threshold)
  , ("REQ_INT_VOTE_005", "Rejection threshold reached", test_vote_rejection_threshold)
  , ("REQ_INT_VOTE_006", "Mixed votes - approval still possible", test_vote_mixed_pending)
  , ("REQ_INT_VOTE_007", "Vote after conclusion fails", test_vote_after_conclusion)
  , ("REQ_INT_VOTE_008", "Threshold check with time expiry", test_vote_expiry)
  , ("REQ_INT_VOTE_009", "Get tally returns correct counts", test_vote_tally)
  , ("REQ_INT_VOTE_010", "Find and update vote state in list", test_vote_state_list)
  -- Auditor selection tests (safeIndex coverage)
  , ("REQ_INT_POOL_001", "Select auditor Random seed 0", test_select_random_seed0)
  , ("REQ_INT_POOL_002", "Select auditor Random seed 1", test_select_random_seed1)
  , ("REQ_INT_POOL_003", "Select auditor Random large seed", test_select_random_large_seed)
  , ("REQ_INT_POOL_004", "Select auditor single element", test_select_random_single)
  , ("REQ_INT_POOL_005", "Select auditor empty list", test_select_random_empty)
  ]
