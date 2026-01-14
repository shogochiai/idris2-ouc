||| AuditorPool Vote Module Tests
|||
||| Tests for n-of-m threshold voting functionality.
module AuditorPool.Tests.VoteTests

import FRMonad.Core
import OUC.Functions.Core
import AuditorPool.Vote
import Data.List

%default covering

-- =============================================================================
-- Test Helpers
-- =============================================================================

testPrincipal1 : ICPrincipal
testPrincipal1 = MkICPrincipal "aaaaa-aa"

testPrincipal2 : ICPrincipal
testPrincipal2 = MkICPrincipal "bbbbb-bb"

testPrincipal3 : ICPrincipal
testPrincipal3 = MkICPrincipal "ccccc-cc"

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

testOUAddress : EvmAddress
testOUAddress = MkEvmAddress "0x1234567890123456789012345678901234567890"

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
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok newState _ => do
      let tally = getTally newState
      pure $ tally.approveCount == 1 && tally.rejectCount == 0

||| REQ_INT_VOTE_002: Submit vote fails for unassigned auditor
test_vote_unassigned_fails : IO Bool
test_vote_unassigned_fails = do
  let state = makeTestVoteState
      unassigned = MkAuditorId (MkICPrincipal "unknown-principal")
  case submitVote state unassigned True baseTime of
    Fail _ _ => pure True  -- Expected failure
    Ok _ _ => pure False   -- Should have failed

||| REQ_INT_VOTE_003: Duplicate vote fails
test_vote_duplicate_fails : IO Bool
test_vote_duplicate_fails = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor1 False baseTime of
        Fail _ _ => pure True   -- Expected: duplicate vote rejected
        Ok _ _ => pure False    -- Should have failed

||| REQ_INT_VOTE_004: Approval threshold reached (2-of-3)
test_vote_approval_threshold : IO Bool
test_vote_approval_threshold = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 True (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          pure $ state3.result == Just ApprovalReached

||| REQ_INT_VOTE_005: Rejection threshold reached (2 rejections blocks approval)
test_vote_rejection_threshold : IO Bool
test_vote_rejection_threshold = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 False baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 False (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          pure $ state3.result == Just RejectionReached

||| REQ_INT_VOTE_006: Mixed votes - approval still possible
test_vote_mixed_pending : IO Bool
test_vote_mixed_pending = do
  let state = makeTestVoteState
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 False (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          -- 1 approve, 1 reject, 1 pending - still can reach 2 approvals
          pure $ state3.result == Nothing

||| REQ_INT_VOTE_007: Vote after conclusion fails
test_vote_after_conclusion : IO Bool
test_vote_after_conclusion = do
  let state = makeTestVoteState
  -- First reach approval threshold
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 True (baseTime + 1000) of
        Fail _ _ => pure False
        Ok state3 _ =>
          -- Now try to vote after conclusion
          case submitVote state3 testAuditor3 False (baseTime + 2000) of
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
  case submitVote state testAuditor1 True baseTime of
    Fail _ _ => pure False
    Ok state2 _ =>
      case submitVote state2 testAuditor2 False (baseTime + 1000) of
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
      case submitVote found testAuditor1 True baseTime of
        Fail _ _ => pure False
        Ok updated _ => do
          let newStates = updateVoteState states updated
          case findVoteState newStates testProposalId of
            Nothing => pure False
            Just final =>
              pure $ (getTally final).approveCount == 1

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
  ]
