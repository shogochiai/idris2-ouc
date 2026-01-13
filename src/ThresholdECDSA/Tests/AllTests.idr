||| Threshold ECDSA Tests
|||
||| SPEC-Test Parity tests for t-ECDSA operations.
module ThresholdECDSA.Tests.AllTests

import ThresholdECDSA.Core
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
-- Key Management Tests
-- =============================================================================

test_key_001 : () -> Bool
test_key_001 () =
  productionKey.curve == Secp256k1

test_key_002 : () -> Bool
test_key_002 () =
  productionKey.name == "key_1"

test_key_003 : () -> Bool
test_key_003 () =
  testKey.name == "test_key_1"

test_key_004 : () -> Bool
test_key_004 () =
  localKey.name == "dfx_test_key"

-- =============================================================================
-- Derivation Path Tests
-- =============================================================================

test_path_001 : () -> Bool
test_path_001 () =
  bip44Purpose == 0x8000002C

test_path_002 : () -> Bool
test_path_002 () =
  let path = evmDerivationPath 1
  in length path.segments == 5

test_path_003 : () -> Bool
test_path_003 () =
  let path = evmDerivationPath 1
  in case getAt 4 path.segments of
       Just seg => seg == 1  -- chainId = 1
       Nothing => False

-- =============================================================================
-- Cycle Cost Tests
-- =============================================================================

test_sign_003 : () -> Bool
test_sign_003 () =
  signCycles Production == 25000000000

test_sign_003b : () -> Bool
test_sign_003b () =
  signCycles Test == 10000000000

test_sign_003c : () -> Bool
test_sign_003c () =
  signCycles Local == 0

-- =============================================================================
-- Type Tests
-- =============================================================================

test_type_001 : () -> Bool
test_type_001 () =
  show Secp256k1 == "secp256k1"

test_type_002 : () -> Bool
test_type_002 () =
  productionKey == MkKeyId Secp256k1 "key_1"

test_type_003 : () -> Bool
test_type_003 () =
  let path = MkDerivationPath [1, 2, 3]
  in length path.segments == 3

test_type_005 : () -> Bool
test_type_005 () =
  show Pending == "Pending" &&
  show Success == "Success"

test_type_007 : () -> Bool
test_type_007 () =
  let addr = MkEvmAddress (replicate 20 0)
  in length addr.bytes == 20

-- =============================================================================
-- Key Type Conversion Tests
-- =============================================================================

test_keytype_prod : () -> Bool
test_keytype_prod () =
  keyTypeToInt Production == 0

test_keytype_test : () -> Bool
test_keytype_test () =
  keyTypeToInt Test == 1

test_keytype_local : () -> Bool
test_keytype_local () =
  keyTypeToInt Local == 2

test_keyid_to_type : () -> Bool
test_keyid_to_type () =
  keyIdToType productionKey == Production &&
  keyIdToType testKey == Test &&
  keyIdToType localKey == Local

-- =============================================================================
-- All Tests
-- =============================================================================

||| All SPEC-aligned tests
export
allTests : List TestDef
allTests =
  -- Key Management
  [ test "REQ_ECDSA_KEY_001" "secp256k1 curve support" test_key_001
  , test "REQ_ECDSA_KEY_002" "Production key name" test_key_002
  , test "REQ_ECDSA_KEY_003" "Test key name" test_key_003
  , test "REQ_ECDSA_KEY_004" "Local key name" test_key_004

  -- Derivation Path
  , test "REQ_ECDSA_PATH_001" "BIP-44 purpose constant" test_path_001
  , test "REQ_ECDSA_PATH_002" "EVM derivation path length" test_path_002
  , test "REQ_ECDSA_PATH_003" "Chain ID in derivation path" test_path_003

  -- Signing
  , test "REQ_ECDSA_SIGN_003" "Production cycle cost" test_sign_003
  , test "REQ_ECDSA_SIGN_003b" "Test cycle cost" test_sign_003b
  , test "REQ_ECDSA_SIGN_003c" "Local cycle cost" test_sign_003c

  -- Types
  , test "REQ_TYPE_ECDSA_001" "EcdsaCurve Show" test_type_001
  , test "REQ_TYPE_ECDSA_002" "KeyId equality" test_type_002
  , test "REQ_TYPE_ECDSA_003" "DerivationPath segments" test_type_003
  , test "REQ_TYPE_ECDSA_005" "SignStatus Show" test_type_005
  , test "REQ_TYPE_ECDSA_007" "EvmAddress bytes" test_type_007

  -- Key type conversion
  , test "REQ_ECDSA_FFI_002a" "keyTypeToInt Production" test_keytype_prod
  , test "REQ_ECDSA_FFI_002b" "keyTypeToInt Test" test_keytype_test
  , test "REQ_ECDSA_FFI_002c" "keyTypeToInt Local" test_keytype_local
  , test "REQ_ECDSA_FFI_002d" "keyIdToType round-trip" test_keyid_to_type
  ]

||| Run all tests and return (passed, failed)
export
runAllTests : (Nat, Nat)
runAllTests =
  let results = map (\t => t.run ()) allTests
      passed = length $ filter id results
      failed = length $ filter not results
  in (passed, failed)
