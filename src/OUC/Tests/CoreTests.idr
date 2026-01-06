||| OUC Core Module Tests
module OUC.Tests.CoreTests

import FRMonad.Core
import OUC.Core
import Data.List

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

||| Assert FR is Ok
assertOk : Show a => FR a -> IO Bool
assertOk (Ok _ _)   = pure True
assertOk (Fail f e) = do
  putStrLn $ "Expected Ok but got: " ++ show f
  pure False

||| Assert FR is Fail with specific type
assertFail : FR a -> IO Bool
assertFail (Ok _ _)   = do
  putStrLn "Expected Fail but got Ok"
  pure False
assertFail (Fail _ _) = pure True

-- =============================================================================
-- OUC_PROP_001: Proposals transition through valid status sequence
-- =============================================================================

||| Test proposal lifecycle: Pending -> UnderReview -> Approved -> Executed
test_proposal_lifecycle : IO Bool
test_proposal_lifecycle = do
  let state0 = initialState testPrincipal
      now = 1704067200000000000  -- Some timestamp

  -- Step 1: Submit proposal (Pending)
  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test upgrade" "0x1234" now of
    Fail f e => do
      putStrLn $ "Failed to submit proposal: " ++ show f
      pure False
    Ok (state1, pid) e1 => do
      -- Verify status is Pending
      case findProposal state1 pid of
        Fail _ _ => do
          putStrLn "Failed to find submitted proposal"
          pure False
        Ok proposal _ => do
          if proposal.status /= Pending
            then do
              putStrLn $ "Expected Pending but got " ++ show proposal.status
              pure False
            else do
              -- Step 2: Assign auditor (UnderReview)
              let aid = MkAuditorId testPrincipal
              case assignAuditor state1 pid aid (now + 1000) of
                Fail f _ => do
                  putStrLn $ "Failed to assign auditor: " ++ show f
                  pure False
                Ok state2 _ => do
                  case findProposal state2 pid of
                    Fail _ _ => pure False
                    Ok proposal2 _ => do
                      if proposal2.status /= UnderReview
                        then do
                          putStrLn $ "Expected UnderReview but got " ++ show proposal2.status
                          pure False
                        else do
                          -- Step 3: Submit approval (Approved)
                          case submitReview state2 pid aid ApproveUpgrade "Looks good" "sig" (now + 2000) of
                            Fail f _ => do
                              putStrLn $ "Failed to submit review: " ++ show f
                              pure False
                            Ok state3 _ => do
                              case findProposal state3 pid of
                                Fail _ _ => pure False
                                Ok proposal3 _ => do
                                  if proposal3.status /= Approved
                                    then do
                                      putStrLn $ "Expected Approved but got " ++ show proposal3.status
                                      pure False
                                    else do
                                      -- Step 4: Mark executed
                                      case markExecuted state3 pid "0xtxhash" (now + 3000) of
                                        Fail f _ => do
                                          putStrLn $ "Failed to mark executed: " ++ show f
                                          pure False
                                        Ok state4 _ => do
                                          case findProposal state4 pid of
                                            Fail _ _ => pure False
                                            Ok proposal4 _ =>
                                              pure (proposal4.status == Executed)

-- =============================================================================
-- OUC_PROP_002: Proposal IDs are unique and monotonically increasing
-- =============================================================================

||| Test that proposal IDs are unique and increasing
test_proposal_ids_unique : IO Bool
test_proposal_ids_unique = do
  let state0 = initialState testPrincipal
      now = 1704067200000000000

  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "First" "0x1" now of
    Fail _ _ => pure False
    Ok (state1, pid1) _ =>
      case submitProposal state1 testChain testTarget testNewImpl testOU testPrincipal "Second" "0x2" now of
        Fail _ _ => pure False
        Ok (state2, pid2) _ =>
          case submitProposal state2 testChain testTarget testNewImpl testOU testPrincipal "Third" "0x3" now of
            Fail _ _ => pure False
            Ok (_, pid3) _ =>
              -- IDs should be 1, 2, 3 and increasing
              pure (pid1.value < pid2.value && pid2.value < pid3.value)

-- =============================================================================
-- OUC_PROP_004: Only Pending proposals can be assigned auditors
-- =============================================================================

||| Test that non-Pending proposals cannot be assigned
test_assign_non_pending_fails : IO Bool
test_assign_non_pending_fails = do
  let state0 = initialState testPrincipal
      now = 1704067200000000000
      aid = MkAuditorId testPrincipal

  case submitProposal state0 testChain testTarget testNewImpl testOU testPrincipal "Test" "0x1" now of
    Fail _ _ => pure False
    Ok (state1, pid) _ =>
      -- First assign (should succeed)
      case assignAuditor state1 pid aid now of
        Fail _ _ => pure False
        Ok state2 _ =>
          -- Second assign should fail (status is UnderReview)
          case assignAuditor state2 pid aid now of
            Fail (InvalidState _) _ => pure True
            _ => pure False

-- =============================================================================
-- OUC_FAIL_001: Missing proposal returns NotFound
-- =============================================================================

||| Test that missing proposal returns NotFound
test_missing_proposal_not_found : IO Bool
test_missing_proposal_not_found = do
  let state = initialState testPrincipal
      fakePid = MkProposalId 9999

  case findProposal state fakePid of
    Fail (NotFound _) _ => pure True
    Ok _ _ => do
      putStrLn "Expected NotFound but got Ok"
      pure False
    Fail other _ => do
      putStrLn $ "Expected NotFound but got " ++ show other
      pure False

-- =============================================================================
-- Test Collection
-- =============================================================================

public export
allTests : List (String, IO Bool)
allTests =
  [ ("OUC_PROP_001: Proposal lifecycle transitions", test_proposal_lifecycle)
  , ("OUC_PROP_002: Proposal IDs unique and increasing", test_proposal_ids_unique)
  , ("OUC_PROP_004: Assign non-pending fails", test_assign_non_pending_fails)
  , ("OUC_FAIL_001: Missing proposal returns NotFound", test_missing_proposal_not_found)
  ]

||| Run all tests
export
runAllTests : IO ()
runAllTests = do
  putStrLn "=== OUC Core Tests ==="
  results <- traverse runTest allTests
  let passed = length (filter id results)
      total = length results
  putStrLn $ "\nPassed: " ++ show passed ++ "/" ++ show total
  where
    runTest : (String, IO Bool) -> IO Bool
    runTest (name, test) = do
      putStr $ name ++ "... "
      result <- test
      putStrLn $ if result then "PASS" else "FAIL"
      pure result

main : IO ()
main = runAllTests
