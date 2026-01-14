||| MultiChain Test Suite
|||
||| SPEC-Test Parity tests for OU Registry (マルチチェーン OU 管理).
||| Note: Cross-Chain execution は不要。各 OU が独立して UpgradeProposal を処理。
module MultiChain.Tests.AllTests

import MultiChain.Registry
import MultiChain.OURegistry
import MultiChain.AuditorRelay
import Data.List

%default total

-- =============================================================================
-- Test Infrastructure
-- =============================================================================

||| Test definition
public export
record TestDef where
  constructor MkTestDef
  specId      : String
  description : String
  run         : () -> Bool

||| Create test from spec ID
test : String -> String -> (() -> Bool) -> TestDef
test sid desc fn = MkTestDef sid desc fn

-- =============================================================================
-- Chain ID Tests
-- =============================================================================

test_REG_001 : () -> Bool
test_REG_001 () =
  ethereumMainnet.value == 1 &&
  arbitrumOne.value == 42161 &&
  baseMainnet.value == 8453

test_WKC_001 : () -> Bool
test_WKC_001 () = ethereumMainnet.value == 1

test_WKC_002 : () -> Bool
test_WKC_002 () = arbitrumOne.value == 42161

test_WKC_003 : () -> Bool
test_WKC_003 () = baseMainnet.value == 8453

-- =============================================================================
-- Chain Config Tests
-- =============================================================================

test_REG_002 : () -> Bool
test_REG_002 () =
  defaultEthereumConfig.name == "Ethereum" &&
  defaultEthereumConfig.confirmations == 12 &&
  defaultEthereumConfig.isActive == True

test_GAS_002 : () -> Bool
test_GAS_002 () =
  defaultEthereumConfig.confirmations == 12

test_GAS_003 : () -> Bool
test_GAS_003 () =
  defaultArbitrumConfig.confirmations == 1 &&
  defaultBaseConfig.confirmations == 1

-- =============================================================================
-- Registry Tests
-- =============================================================================

test_REG_003 : () -> Bool
test_REG_003 () =
  let reg = initDefaultRegistry 1000
  in length reg.chains == 3 &&
     reg.defaultChain == ethereumMainnet

test_WKC_004 : () -> Bool
test_WKC_004 () =
  let reg = initDefaultRegistry 1000
  in getChainCount reg == 3

test_REG_004 : () -> Bool
test_REG_004 () =
  let reg = initDefaultRegistry 1000
      dupConfig = MkChainConfig ethereumMainnet "Duplicate" "" [] zeroAddress zeroAddress 0 0 0 True 0
  in case addChain reg dupConfig 1001 of
       Left _ => True   -- Expected: duplicate rejected
       Right _ => False

test_REG_005 : () -> Bool
test_REG_005 () =
  let reg = initDefaultRegistry 1000
  in case getChain reg ethereumMainnet of
       Just c => c.name == "Ethereum"
       Nothing => False

test_REG_006 : () -> Bool
test_REG_006 () =
  let reg = initDefaultRegistry 1000
      active = getActiveChains reg
  in length active == 3  -- All default chains are active

test_REG_007 : () -> Bool
test_REG_007 () =
  let reg = initDefaultRegistry 1000
      fakeChain = MkChainId 99999
  in case removeChain reg fakeChain 1001 of
       Left _ => True   -- Expected: not found
       Right _ => False

test_REG_008 : () -> Bool
test_REG_008 () =
  let reg = initDefaultRegistry 1000
      fakeChain = MkChainId 99999
  in case setDefaultChain reg fakeChain 1001 of
       Left _ => True   -- Expected: not found
       Right _ => False

-- =============================================================================
-- Chain Status Tests
-- =============================================================================

test_STS_001 : () -> Bool
test_STS_001 () =
  show Healthy == "Healthy" &&
  show Offline == "Offline"

test_STS_002 : () -> Bool
test_STS_002 () =
  let reg = emptyRegistry
      inactiveConfig = { isActive := False } defaultEthereumConfig
  in case addChain reg inactiveConfig 1000 of
       Left _ => False
       Right reg2 =>
         case activateChain reg2 ethereumMainnet 1001 of
           Left _ => False
           Right reg3 =>
             case getChain reg3 ethereumMainnet of
               Just c => c.isActive == True
               Nothing => False

test_STS_003 : () -> Bool
test_STS_003 () =
  let reg = initDefaultRegistry 1000
  in case deactivateChain reg ethereumMainnet 1001 of
       Left _ => False
       Right reg2 =>
         case getChain reg2 ethereumMainnet of
           Just c => c.isActive == False
           Nothing => False

-- =============================================================================
-- RPC Tests
-- =============================================================================

test_RPC_001 : () -> Bool
test_RPC_001 () =
  length defaultEthereumConfig.rpcBackups > 0

-- =============================================================================
-- Gas Tests
-- =============================================================================

test_GAS_001 : () -> Bool
test_GAS_001 () =
  -- 12000 basis points = 120%
  defaultEthereumConfig.gasMultiplier == 12000

-- =============================================================================
-- Type Tests
-- =============================================================================

test_TYPE_001 : () -> Bool
test_TYPE_001 () =
  let c1 = MkChainId 1
      c2 = MkChainId 1
  in c1 == c2

test_TYPE_002 : () -> Bool
test_TYPE_002 () =
  let a = MkEvmAddress "0x1234"
  in show a == "0x1234"

test_TYPE_003 : () -> Bool
test_TYPE_003 () =
  show defaultEthereumConfig == "Ethereum (1)"

test_TYPE_004 : () -> Bool
test_TYPE_004 () =
  Healthy == Healthy &&
  not (Healthy == Offline)

test_TYPE_005 : () -> Bool
test_TYPE_005 () =
  length emptyRegistry.chains == 0

-- =============================================================================
-- OU Registry Tests
-- =============================================================================

test_OUR_001 : () -> Bool
test_OUR_001 () =
  let ou = MkRegisteredOU 0 ethereumMainnet (MkEvmAddress "0x1234") zeroAddress 1000 1000 True
  in ou.ouId == 0 && ou.chainId == ethereumMainnet && ou.isActive == True

test_OUR_002 : () -> Bool
test_OUR_002 () =
  let snapshot = MkOUStateSnapshot 0 10 3 5 2 4 1000 12345
  in snapshot.proposalCount == 10 && snapshot.pendingCount == 3

test_OUR_003 : () -> Bool
test_OUR_003 () =
  let (state1, id1) = registerOU emptyOURegistry ethereumMainnet (MkEvmAddress "0x1") zeroAddress 1000
      (state2, id2) = registerOU state1 arbitrumOne (MkEvmAddress "0x2") zeroAddress 1001
  in id1 == 0 && id2 == 1 && state2.nextOuId == 2

test_OUR_004 : () -> Bool
test_OUR_004 () =
  let (state, _) = registerOU emptyOURegistry ethereumMainnet (MkEvmAddress "0x1") zeroAddress 1000
  in case findOU state 0 of
       Just ou => ou.chainId == ethereumMainnet
       Nothing => False

test_OUR_005 : () -> Bool
test_OUR_005 () =
  let (state1, _) = registerOU emptyOURegistry ethereumMainnet (MkEvmAddress "0x1") zeroAddress 1000
      (state2, _) = registerOU state1 ethereumMainnet (MkEvmAddress "0x2") zeroAddress 1001
      (state3, _) = registerOU state2 arbitrumOne (MkEvmAddress "0x3") zeroAddress 1002
  in length (findOUsByChain state3 ethereumMainnet) == 2

test_OUR_006 : () -> Bool
test_OUR_006 () =
  let (state1, _) = registerOU emptyOURegistry ethereumMainnet (MkEvmAddress "0x1") zeroAddress 1000
      state2 = deactivateOU state1 0 1001
  in length (getActiveOUs state2) == 0

test_OUR_007 : () -> Bool
test_OUR_007 () =
  let snapshot1 = MkOUStateSnapshot 0 10 3 5 2 4 1000 12345
      snapshot2 = MkOUStateSnapshot 1 20 5 10 5 6 1000 12346
      state = { snapshots := [snapshot1, snapshot2] } emptyOURegistry
      stats = aggregateStats state 2000
  in stats.totalProposals == 30 && stats.totalPending == 8

-- =============================================================================
-- Auditor Relay Tests
-- =============================================================================

test_REL_001 : () -> Bool
test_REL_001 () =
  let sig = MkEvmSignature "abcd" "efgh" 27
      approval = MkAuditorApproval (MkEvmAddress "0xAuditor") 0 1 True sig 1000
  in approval.approve == True && approval.proposalId == 1

test_REL_002 : () -> Bool
test_REL_002 () =
  let collection = MkPendingApprovalCollection 0 1 ethereumMainnet (MkEvmAddress "0xOU") 2 [] [] 1000 2000
  in collection.requiredCount == 2 && length collection.approvals == 0

test_REL_003 : () -> Bool
test_REL_003 () =
  let sig = MkEvmSignature "a" "b" 27
      approval1 = MkAuditorApproval (MkEvmAddress "0xA1") 0 1 True sig 1000
      approval2 = MkAuditorApproval (MkEvmAddress "0xA2") 0 1 True sig 1001
      collection = MkPendingApprovalCollection 0 1 ethereumMainnet (MkEvmAddress "0xOU") 2 [approval1, approval2] [] 1000 2000
  in isApprovalThresholdMet collection == True

test_REL_004 : () -> Bool
test_REL_004 () =
  let sig = MkEvmSignature "a" "b" 27
      approval = MkAuditorApproval (MkEvmAddress "0xUnknown") 0 1 True sig 1000
      state = emptyRelayState
  in case submitApproval state approval of
       Left msg => True   -- Expected: not registered
       Right _ => False

test_REL_005 : () -> Bool
test_REL_005 () =
  let state1 = registerAuditor emptyRelayState (MkEvmAddress "0xA1")
      state2 = startCollection state1 0 1 ethereumMainnet (MkEvmAddress "0xOU") 1000
      sig = MkEvmSignature "a" "b" 27
      approval = MkAuditorApproval (MkEvmAddress "0xA1") 0 1 True sig 1001
  in case submitApproval state2 approval of
       Left _ => False
       Right state3 =>
         case submitApproval state3 approval of
           Left msg => True   -- Expected: duplicate
           Right _ => False

test_REL_006 : () -> Bool
test_REL_006 () =
  let collection = MkPendingApprovalCollection 0 1 ethereumMainnet (MkEvmAddress "0xOU") 2 [] [] 1000 2000
  in isExpired collection 2001 == True && isExpired collection 1500 == False

test_REL_007 : () -> Bool
test_REL_007 () =
  let sig = MkEvmSignature "a" "b" 27
      approval = MkAuditorApproval (MkEvmAddress "0xA1") 0 1 True sig 1000
      collection = MkPendingApprovalCollection 0 1 ethereumMainnet (MkEvmAddress "0xOU") 2 [approval] [] 1000 2000
      calldata = buildRelayCalldata collection
  in calldata.proposalId == 1 && length calldata.signatures == 1

-- =============================================================================
-- All Tests
-- =============================================================================

||| All SPEC-aligned tests
export
allTests : List TestDef
allTests =
  -- Chain Registry
  [ test "REQ_MC_REG_001" "ChainId identifies chains" test_REG_001
  , test "REQ_MC_REG_002" "ChainConfig contains metadata" test_REG_002
  , test "REQ_MC_REG_003" "ChainRegistry maintains chains" test_REG_003
  , test "REQ_MC_REG_004" "addChain rejects duplicates" test_REG_004
  , test "REQ_MC_REG_005" "getChain returns config" test_REG_005
  , test "REQ_MC_REG_006" "getActiveChains filters" test_REG_006
  , test "REQ_MC_REG_007" "removeChain fails for unknown" test_REG_007
  , test "REQ_MC_REG_008" "setDefaultChain requires registered" test_REG_008

  -- Chain Status
  , test "REQ_MC_STS_001" "ChainStatus operational state" test_STS_001
  , test "REQ_MC_STS_002" "activateChain sets active" test_STS_002
  , test "REQ_MC_STS_003" "deactivateChain sets inactive" test_STS_003

  -- RPC
  , test "REQ_MC_RPC_001" "Backup endpoints exist" test_RPC_001

  -- Gas
  , test "REQ_MC_GAS_001" "gasMultiplier in basis points" test_GAS_001
  , test "REQ_MC_GAS_002" "Ethereum 12 confirmations" test_GAS_002
  , test "REQ_MC_GAS_003" "L2s 1 confirmation" test_GAS_003

  -- Well-Known Chains
  , test "REQ_MC_WKC_001" "ethereumMainnet chainId 1" test_WKC_001
  , test "REQ_MC_WKC_002" "arbitrumOne chainId 42161" test_WKC_002
  , test "REQ_MC_WKC_003" "baseMainnet chainId 8453" test_WKC_003
  , test "REQ_MC_WKC_004" "Default registry 3 chains" test_WKC_004

  -- Types
  , test "REQ_TYPE_MC_001" "ChainId equality" test_TYPE_001
  , test "REQ_TYPE_MC_002" "EvmAddress show" test_TYPE_002
  , test "REQ_TYPE_MC_003" "ChainConfig show" test_TYPE_003
  , test "REQ_TYPE_MC_004" "ChainStatus equality" test_TYPE_004
  , test "REQ_TYPE_MC_005" "emptyRegistry empty" test_TYPE_005

  -- OU Registry
  , test "REQ_MC_OUR_001" "RegisteredOU tracks OU" test_OUR_001
  , test "REQ_MC_OUR_002" "OUStateSnapshot captures state" test_OUR_002
  , test "REQ_MC_OUR_003" "registerOU assigns unique ID" test_OUR_003
  , test "REQ_MC_OUR_004" "findOU returns OU by ID" test_OUR_004
  , test "REQ_MC_OUR_005" "findOUsByChain filters by chain" test_OUR_005
  , test "REQ_MC_OUR_006" "getActiveOUs filters inactive" test_OUR_006
  , test "REQ_MC_OUR_007" "aggregateStats sums snapshots" test_OUR_007

  -- Auditor Relay
  , test "REQ_MC_REL_001" "AuditorApproval contains signature" test_REL_001
  , test "REQ_MC_REL_002" "PendingApprovalCollection tracks threshold" test_REL_002
  , test "REQ_MC_REL_003" "isApprovalThresholdMet checks n-of-m" test_REL_003
  , test "REQ_MC_REL_004" "submitApproval rejects unregistered" test_REL_004
  , test "REQ_MC_REL_005" "submitApproval rejects duplicate" test_REL_005
  , test "REQ_MC_REL_006" "Collection expires after timeout" test_REL_006
  , test "REQ_MC_REL_007" "buildRelayCalldata encodes signatures" test_REL_007
  ]

||| Run all tests and print results
export
runAllTests : IO ()
runAllTests = do
  let results = map (\t => (t.specId, t.description, t.run ())) allTests
      passed = length $ filter (\(_, _, r) => r) results
      failed = length $ filter (\(_, _, r) => not r) results
  putStrLn "=== MultiChain Tests ==="
  for_ results $ \(sid, desc, r) =>
    putStrLn $ (if r then "[PASS] " else "[FAIL] ") ++ sid ++ ": " ++ desc
  putStrLn $ "=== Results: " ++ show passed ++ "/" ++ show (passed + failed) ++ " passed ==="
