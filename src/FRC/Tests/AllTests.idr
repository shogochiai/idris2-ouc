||| FRC Module Tests
||| Tests for Failure-Recovery Calculus modules
module FRC.Tests.AllTests

import FRC.Core
import FRC.Conflict
import FRC.Evidence
import FRC.Outcome
import FRC.Cycles
import FRC.Upgrade
import FRC.HttpOutcall
import FRC.Chain
import Data.List

%default covering

-- =============================================================================
-- Test Helpers
-- =============================================================================

||| Check if FR is Ok
isOk : FR a -> Bool
isOk (Ok _ _)   = True
isOk (Fail _ _) = False

||| Check if FR is Fail
isFail : FR a -> Bool
isFail = not . isOk

||| Get evidence from FR
getEvidence : FR a -> Evidence
getEvidence (Ok _ e)   = e
getEvidence (Fail _ e) = e

-- =============================================================================
-- FRC_CONFLICT_001: Severity classification is correct
-- =============================================================================

test_severity_classification : IO Bool
test_severity_classification = pure $
  severity (Unauthorized "test") == High &&
  severity (InsufficientCycles 100 "test") == Critical &&
  severity (ValidationError "test") == Medium &&
  severity (NotFound "test") == Low

-- =============================================================================
-- FRC_CONFLICT_002: Category classification is correct
-- =============================================================================

test_category_classification : IO Bool
test_category_classification = pure $
  category (Unauthorized "test") == SecurityConflict &&
  category (InsufficientCycles 100 "test") == ResourceConflict &&
  category (InvalidState "test") == StateConflict &&
  category (Timeout "test") == NetworkConflict

-- =============================================================================
-- FRC_CONFLICT_003: Retryability is correct
-- =============================================================================

test_retryability : IO Bool
test_retryability = pure $
  isRetryable (Timeout "test") == True &&
  isRetryable (CallError "test") == True &&
  isRetryable (Unauthorized "test") == False &&
  isRetryable (InvalidState "test") == False

-- =============================================================================
-- FRC_EVIDENCE_001: Evidence phase tracking works
-- =============================================================================

test_evidence_phase : IO Bool
test_evidence_phase = pure $
  let e1 = mkEvidence Update "test" "detail"
      e2 = mkEvidence Query "query" "read"
      e3 = mkEvidence Init "init" "setup"
  in e1.phase == Update && e2.phase == Query && e3.phase == Init

-- =============================================================================
-- FRC_EVIDENCE_002: Evidence merging preserves info
-- =============================================================================

test_evidence_merge : IO Bool
test_evidence_merge = pure $
  let e1 = mkEvidence Update "op1" "detail1"
      e2 = mkEvidence Query "op2" "detail2"
      merged = e1 <+> e2
  in length merged.tags >= length e1.tags

-- =============================================================================
-- FRC_OUTCOME_001: FR monad bind works correctly
-- =============================================================================

test_fr_bind : IO Bool
test_fr_bind = pure $
  let result : FR Nat
      result = do
        x <- pure 10
        y <- pure 20
        pure (x + y)
  in case result of
       Ok v _ => v == 30
       Fail _ _ => False

-- =============================================================================
-- FRC_OUTCOME_002: FR monad fail propagates
-- =============================================================================

test_fr_fail_propagates : IO Bool
test_fr_fail_propagates = pure $
  let result : FR Nat
      result = do
        x <- pure 10
        _ <- fail (NotFound "missing")
        pure x
  in isFail result

-- =============================================================================
-- FRC_OUTCOME_003: orElse provides fallback
-- =============================================================================

test_fr_orElse : IO Bool
test_fr_orElse = pure $
  let primary : FR Nat
      primary = fail (NotFound "missing")
      fallback : FR Nat
      fallback = pure 42
      result = primary `orElse` fallback
  in case result of
       Ok v _ => v == 42
       Fail _ _ => False

-- =============================================================================
-- FRC_OUTCOME_004: guard creates conditional failure
-- =============================================================================

test_fr_guard : IO Bool
test_fr_guard = pure $
  let ok = guard Update "test" True (ValidationError "should not happen")
      notOk = guard Update "test" False (ValidationError "expected")
  in isOk ok && isFail notOk

-- =============================================================================
-- FRC_CYCLES_001: Budget consumption works
-- =============================================================================

test_budget_consume : IO Bool
test_budget_consume = pure $
  let budget = limitedBudget 1000 500
      consumed = consumeCycles 100 budget
  in case consumed of
       Just b => b.consumed == 100 && remaining b == 400
       Nothing => False

-- =============================================================================
-- FRC_CYCLES_002: Budget exhaustion detected
-- =============================================================================

test_budget_exhaustion : IO Bool
test_budget_exhaustion = pure $
  let budget = limitedBudget 100 50
      result = consumeCycles 100 budget
  in isNothing result
  where
    isNothing : Maybe a -> Bool
    isNothing Nothing = True
    isNothing (Just _) = False

-- =============================================================================
-- FRC_CYCLES_003: Cost calculation works
-- =============================================================================

test_cost_calculation : IO Bool
test_cost_calculation = pure $
  let fixed = calculateCost (FixedCost 100) 999
      perByte = calculateCost (PerByteCost 10 5) 20
  in fixed == 100 && perByte == 110

-- =============================================================================
-- FRC_UPGRADE_001: Version comparison works
-- =============================================================================

test_version_compare : IO Bool
test_version_compare = pure $
  let v1 = MkVersion 1 0 0
      v2 = MkVersion 1 1 0
      v3 = MkVersion 2 0 0
  in v1 < v2 && v2 < v3 && v1 < v3

-- =============================================================================
-- FRC_UPGRADE_002: Version compatibility check
-- =============================================================================

test_version_compatible : IO Bool
test_version_compatible = pure $
  let v1 = MkVersion 1 0 0
      v2 = MkVersion 1 5 3
      v3 = MkVersion 2 0 0
  in isCompatible v1 v2 && not (isCompatible v1 v3)

-- =============================================================================
-- FRC_UPGRADE_003: Upgrade state machine transitions
-- =============================================================================

test_upgrade_transitions : IO Bool
test_upgrade_transitions = pure $
  let ctx0 = mkUpgradeContext (MkVersion 1 0 0) (MkVersion 1 1 0)
  in case beginUpgrade ctx0 of
       Fail _ _ => False
       Ok ctx1 _ => ctx1.state == PreUpgrading &&
         case completePreUpgrade ctx1 1024 of
           Fail _ _ => False
           Ok ctx2 _ => ctx2.state == Upgrading && ctx2.stableSize == 1024

-- =============================================================================
-- FRC_HTTP_001: Request validation works
-- =============================================================================

test_http_validation : IO Bool
test_http_validation = pure $
  let validReq = mkGetRequest "https://example.com"
      emptyReq = MkHttpRequest "" GET [] Nothing 10000 Nothing
  in isOk (validateRequest validReq) && isFail (validateRequest emptyReq)

-- =============================================================================
-- FRC_HTTP_002: Response status classification
-- =============================================================================

test_http_status : IO Bool
test_http_status = pure $
  let ok = MkHttpResponse 200 [] "ok"
      clientErr = MkHttpResponse 404 [] "not found"
      serverErr = MkHttpResponse 500 [] "error"
  in isSuccess ok && isClientError clientErr && isServerError serverErr

-- =============================================================================
-- FRC_HTTP_003: Cost estimation reasonable
-- =============================================================================

test_http_cost : IO Bool
test_http_cost = pure $
  let req = mkGetRequest "https://example.com"
      cost = estimateHttpCost req
  in cost > 49000000 && cost < 200000000

-- =============================================================================
-- FRC_CHAIN_001: Chain ID lookup correct
-- =============================================================================

test_chain_id : IO Bool
test_chain_id = pure $
  chainId Ethereum == 1 &&
  chainId Polygon == 137 &&
  chainId Base == 8453

-- =============================================================================
-- FRC_CHAIN_002: Block reference serialization
-- =============================================================================

test_block_ref : IO Bool
test_block_ref = pure $
  show Latest == "latest" &&
  show Finalized == "finalized" &&
  show (BlockNumber 100) == "0x64"

-- =============================================================================
-- FRC_CHAIN_003: Transaction status checking
-- =============================================================================

test_tx_status : IO Bool
test_tx_status = pure $
  isTerminal (TxFinalized 100) == True &&
  isTerminal (TxFailed "err") == True &&
  isTerminal TxPending == False &&
  isTerminal (TxConfirmed 100 5) == False

-- =============================================================================
-- FRC_CHAIN_004: Confirmation requirements
-- =============================================================================

test_confirmations : IO Bool
test_confirmations = pure $
  let pending = requireConfirmations 12 TxPending
      confirmed5 = requireConfirmations 12 (TxConfirmed 100 5)
      confirmed15 = requireConfirmations 12 (TxConfirmed 100 15)
      finalized = requireConfirmations 12 (TxFinalized 100)
  in isFail pending && isFail confirmed5 && isOk confirmed15 && isOk finalized

-- =============================================================================
-- Test Collection (AllTestsList convention)
-- =============================================================================

public export
allTests : List (String, IO Bool)
allTests =
  [ ("FRC_CONFLICT_001 Severity classification", test_severity_classification)
  , ("FRC_CONFLICT_002 Category classification", test_category_classification)
  , ("FRC_CONFLICT_003 Retryability check", test_retryability)
  , ("FRC_EVIDENCE_001 Phase tracking", test_evidence_phase)
  , ("FRC_EVIDENCE_002 Evidence merging", test_evidence_merge)
  , ("FRC_OUTCOME_001 FR bind works", test_fr_bind)
  , ("FRC_OUTCOME_002 FR fail propagates", test_fr_fail_propagates)
  , ("FRC_OUTCOME_003 orElse fallback", test_fr_orElse)
  , ("FRC_OUTCOME_004 guard conditional", test_fr_guard)
  , ("FRC_CYCLES_001 Budget consumption", test_budget_consume)
  , ("FRC_CYCLES_002 Budget exhaustion", test_budget_exhaustion)
  , ("FRC_CYCLES_003 Cost calculation", test_cost_calculation)
  , ("FRC_UPGRADE_001 Version comparison", test_version_compare)
  , ("FRC_UPGRADE_002 Version compatibility", test_version_compatible)
  , ("FRC_UPGRADE_003 Upgrade transitions", test_upgrade_transitions)
  , ("FRC_HTTP_001 Request validation", test_http_validation)
  , ("FRC_HTTP_002 Response status", test_http_status)
  , ("FRC_HTTP_003 Cost estimation", test_http_cost)
  , ("FRC_CHAIN_001 Chain ID lookup", test_chain_id)
  , ("FRC_CHAIN_002 Block reference format", test_block_ref)
  , ("FRC_CHAIN_003 Transaction terminal state", test_tx_status)
  , ("FRC_CHAIN_004 Confirmation requirements", test_confirmations)
  ]

-- =============================================================================
-- Test Runner
-- =============================================================================

||| Run all tests
export
runAllTests : IO ()
runAllTests = do
  putStrLn "=== FRC Module Tests ==="
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
