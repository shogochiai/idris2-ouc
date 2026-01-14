||| Candid Hash and Encoding Verification Tests
|||
||| Verifies that Idris2-computed hashes match the hardcoded values in canister_entry.c
||| and that DIDL encoding produces compatible output.
module Candid.Tests.AllTests

import Candid.Hash
import Candid.Chain
import Candid.Leb128
import Candid.Encoder
import Candid.EvmRpc
import Data.Bits
import Data.List

%default total

-- =============================================================================
-- Expected Values from canister_entry.c
-- =============================================================================

-- From canister_entry.c lines 1253-1257:
--   case 11155111: chain_hash = 0x4A0728DA; chain_idx = 0; break;  /* EthSepolia */
--   case 8453:     chain_hash = 0x71972D93; chain_idx = 1; break;  /* BaseMainnet */
--   case 42161:    chain_hash = 0xA2510298; chain_idx = 2; break;  /* ArbitrumOne */
--   default:       chain_hash = 0xAEA329CB; chain_idx = 3; break;  /* EthMainnet */

expectedChainHashes : List (Chain, Bits32, Nat)
expectedChainHashes =
  [ (EthSepolia,  0x4A0728DA, 0)
  , (BaseMainnet, 0x71972D93, 1)
  , (ArbitrumOne, 0xA2510298, 2)
  , (EthMainnet,  0xAEA329CB, 3)
  ]

-- From canister_entry.c lines 1272-1283:
--   offset += encode_leb128_unsigned(buf + offset, 0x0334C0A1);  /* Alchemy */
--   offset += encode_leb128_unsigned(buf + offset, 0x0A211B55);  /* Llama */
--   offset += encode_leb128_unsigned(buf + offset, 0x124F9086);  /* BlockPi */
--   offset += encode_leb128_unsigned(buf + offset, 0x1DC0B759);  /* Cloudflare */
--   offset += encode_leb128_unsigned(buf + offset, 0x1FFFC36B);  /* PublicNode */
--   offset += encode_leb128_unsigned(buf + offset, 0x2B4AB3F4);  /* Ankr */

expectedProviderHashes : List (ServiceProvider, Bits32, Nat)
expectedProviderHashes =
  [ (Alchemy,    0x0334C0A1, 0)
  , (Llama,      0x0A211B55, 1)
  , (BlockPi,    0x124F9086, 2)
  , (Cloudflare, 0x1DC0B759, 3)
  , (PublicNode, 0x1FFFC36B, 4)
  , (Ankr,       0x2B4AB3F4, 5)
  ]

-- =============================================================================
-- Test Helpers
-- =============================================================================

record TestResult where
  constructor MkTestResult
  name    : String
  passed  : Bool
  message : String

showResult : TestResult -> String
showResult r = (if r.passed then "[PASS] " else "[FAIL] ") ++ r.name ++ ": " ++ r.message

-- =============================================================================
-- Chain Hash Tests
-- =============================================================================

testChainHash : (Chain, Bits32, Nat) -> TestResult
testChainHash (c, expectedHash, expectedIdx) =
  let actualHash = chainHash c
      actualIdx  = chainIndex c
      hashOk     = actualHash == expectedHash
      idxOk      = actualIdx == expectedIdx
  in MkTestResult
       ("Chain " ++ show c)
       (hashOk && idxOk)
       ("hash=" ++ hashToHex actualHash ++
        (if hashOk then " OK" else " EXPECTED " ++ hashToHex expectedHash) ++
        ", idx=" ++ show actualIdx ++
        (if idxOk then " OK" else " EXPECTED " ++ show expectedIdx))

testAllChainHashes : List TestResult
testAllChainHashes = map testChainHash expectedChainHashes

-- =============================================================================
-- Provider Hash Tests
-- =============================================================================

testProviderHash : (ServiceProvider, Bits32, Nat) -> TestResult
testProviderHash (p, expectedHash, expectedIdx) =
  let actualHash = providerHash p
      actualIdx  = providerIndex p
      hashOk     = actualHash == expectedHash
      idxOk      = actualIdx == expectedIdx
  in MkTestResult
       ("Provider " ++ show p)
       (hashOk && idxOk)
       ("hash=" ++ hashToHex actualHash ++
        (if hashOk then " OK" else " EXPECTED " ++ hashToHex expectedHash) ++
        ", idx=" ++ show actualIdx ++
        (if idxOk then " OK" else " EXPECTED " ++ show expectedIdx))

testAllProviderHashes : List TestResult
testAllProviderHashes = map testProviderHash expectedProviderHashes

-- =============================================================================
-- Run All Tests
-- =============================================================================

allResults : List TestResult
allResults = testAllChainHashes ++ testAllProviderHashes

passCount : Nat
passCount = length (filter (.passed) allResults)

totalCount : Nat
totalCount = length allResults

export
runTests : IO ()
runTests = do
  putStrLn "=== Candid Hash Verification Tests ==="
  putStrLn ""
  putStrLn "Verifying Idris2 computed hashes match canister_entry.c values"
  putStrLn ""
  putStrLn "--- Chain Hashes ---"
  traverse_ (putStrLn . showResult) testAllChainHashes
  putStrLn ""
  putStrLn "--- Provider Hashes ---"
  traverse_ (putStrLn . showResult) testAllProviderHashes
  putStrLn ""
  putStrLn ("=== Results: " ++ show passCount ++ "/" ++ show totalCount ++ " passed ===")
  if passCount == totalCount
    then putStrLn "All tests PASSED - Idris2 hashes match C implementation!"
    else putStrLn "Some tests FAILED - Hash mismatch detected!"

-- =============================================================================
-- Debug: Show All Computed Values
-- =============================================================================

export
showAllChains : IO ()
showAllChains = do
  putStrLn "=== Chain Hash/Index Debug ==="
  putStrLn "Sorted by hash (Candid variant order):"
  traverse_ (putStrLn . ("  " ++) . showChainDebug) chainsSortedByHash

export
showAllProviders : IO ()
showAllProviders = do
  putStrLn "=== Provider Hash/Index Debug ==="
  putStrLn "Sorted by hash (Candid variant order):"
  traverse_ (putStrLn . ("  " ++) . showProviderDebug) providersSortedByHash

-- =============================================================================
-- LEB128 Encoding Tests
-- =============================================================================

testLeb128Unsigned : (Bits64, List Bits8) -> TestResult
testLeb128Unsigned (input, expected) =
  let actual = encodeUnsigned input
  in MkTestResult
       ("LEB128 unsigned " ++ show input)
       (actual == expected)
       (if actual == expected
        then "OK"
        else "FAIL: got " ++ showBytes actual ++ " expected " ++ showBytes expected)

-- Test cases from WebAssembly spec
leb128UnsignedTests : List (Bits64, List Bits8)
leb128UnsignedTests =
  [ (0, [0x00])
  , (1, [0x01])
  , (127, [0x7F])
  , (128, [0x80, 0x01])
  , (624485, [0xE5, 0x8E, 0x26])  -- Classic example
  ]

testLeb128Signed : (Int, List Bits8) -> TestResult
testLeb128Signed (input, expected) =
  let actual = encodeInt input
  in MkTestResult
       ("LEB128 signed " ++ show input)
       (actual == expected)
       (if actual == expected
        then "OK"
        else "FAIL: got " ++ showBytes actual ++ " expected " ++ showBytes expected)

leb128SignedTests : List (Int, List Bits8)
leb128SignedTests =
  [ (0, [0x00])
  , (1, [0x01])
  , (-1, [0x7F])
  , (-21, [0x6B])   -- variant type code
  , (-15, [0x71])   -- text type code
  , (-8, [0x78])    -- nat64 type code
  ]

testAllLeb128 : List TestResult
testAllLeb128 = map testLeb128Unsigned leb128UnsignedTests ++
                map testLeb128Signed leb128SignedTests

-- =============================================================================
-- DIDL Structure Tests
-- =============================================================================

testDIDLMagic : TestResult
testDIDLMagic =
  let encoded = didlEmpty
      magic = take 4 encoded
      expected = [0x44, 0x49, 0x44, 0x4C]
  in MkTestResult
       "DIDL magic header"
       (magic == expected)
       (if magic == expected then "OK (DIDL)" else "FAIL")

testDIDLEmpty : TestResult
testDIDLEmpty =
  let encoded = didlEmpty
      expected = [0x44, 0x49, 0x44, 0x4C, 0x00, 0x00]
  in MkTestResult
       "DIDL empty response"
       (encoded == expected)
       (if encoded == expected then "OK" else "FAIL: " ++ showBytes encoded)

testDIDLStructure : List TestResult
testDIDLStructure = [testDIDLMagic, testDIDLEmpty]

-- =============================================================================
-- EVM RPC Encoding Tests
-- =============================================================================

testEvmRpcStructure : TestResult
testEvmRpcStructure =
  let encoded = encodeEthMainnetRequest "{}" 2000
      -- Check DIDL magic
      magic = take 4 encoded
      magicOk = magic == [0x44, 0x49, 0x44, 0x4C]
      -- Check type count = 2
      typeCount = drop 4 encoded
      typeCountOk = head' typeCount == Just 0x02
  in MkTestResult
       "EVM RPC structure"
       (magicOk && typeCountOk)
       ("magic=" ++ (if magicOk then "OK" else "FAIL") ++
        ", typeCount=" ++ (if typeCountOk then "OK" else "FAIL"))

testEvmRpcChainIndex : TestResult
testEvmRpcChainIndex =
  -- EthMainnet should have chain index 3 (sorted by hash)
  let chainIdx = chainIndex EthMainnet
  in MkTestResult
       "EthMainnet chain index"
       (chainIdx == 3)
       ("idx=" ++ show chainIdx ++ (if chainIdx == 3 then " OK" else " EXPECTED 3"))

testEvmRpcProviderIndex : TestResult
testEvmRpcProviderIndex =
  -- PublicNode should have provider index 4 (sorted by hash)
  let provIdx = providerIndex PublicNode
  in MkTestResult
       "PublicNode provider index"
       (provIdx == 4)
       ("idx=" ++ show provIdx ++ (if provIdx == 4 then " OK" else " EXPECTED 4"))

testEvmRpcEncoding : List TestResult
testEvmRpcEncoding = [testEvmRpcStructure, testEvmRpcChainIndex, testEvmRpcProviderIndex]

-- =============================================================================
-- Run All Tests (Updated)
-- =============================================================================

allResultsExtended : List TestResult
allResultsExtended = testAllChainHashes ++
                     testAllProviderHashes ++
                     testAllLeb128 ++
                     testDIDLStructure ++
                     testEvmRpcEncoding

passCountExtended : Nat
passCountExtended = length (filter (.passed) allResultsExtended)

totalCountExtended : Nat
totalCountExtended = length allResultsExtended

export
runExtendedTests : IO ()
runExtendedTests = do
  putStrLn "=== Candid Encoding Verification Tests ==="
  putStrLn ""
  putStrLn "--- Chain Hashes ---"
  traverse_ (putStrLn . showResult) testAllChainHashes
  putStrLn ""
  putStrLn "--- Provider Hashes ---"
  traverse_ (putStrLn . showResult) testAllProviderHashes
  putStrLn ""
  putStrLn "--- LEB128 Encoding ---"
  traverse_ (putStrLn . showResult) testAllLeb128
  putStrLn ""
  putStrLn "--- DIDL Structure ---"
  traverse_ (putStrLn . showResult) testDIDLStructure
  putStrLn ""
  putStrLn "--- EVM RPC Encoding ---"
  traverse_ (putStrLn . showResult) testEvmRpcEncoding
  putStrLn ""
  putStrLn ("=== Results: " ++ show passCountExtended ++ "/" ++ show totalCountExtended ++ " passed ===")
  if passCountExtended == totalCountExtended
    then putStrLn "All tests PASSED!"
    else putStrLn "Some tests FAILED!"

-- =============================================================================
-- Debug: Show Encoded Request
-- =============================================================================

export
showEncodedRequest : IO ()
showEncodedRequest = do
  let service = MkRpcService EthMainnet PublicNode
  let json = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}"
  let encoded = encodeEvmRpcRequest service json 2000
  putStrLn "=== EVM RPC Request Debug ==="
  putStrLn $ "Chain: " ++ show service.chain ++ " (idx=" ++ show (chainIndex service.chain) ++ ")"
  putStrLn $ "Provider: " ++ show service.provider ++ " (idx=" ++ show (providerIndex service.provider) ++ ")"
  putStrLn $ "JSON: " ++ json
  putStrLn $ "MaxBytes: 2000"
  putStrLn $ "Encoded length: " ++ show (length encoded) ++ " bytes"
  putStrLn $ "First 20 bytes: " ++ showBytes (take 20 encoded)

export
runAllTests : IO ()
runAllTests = runExtendedTests

main : IO ()
main = runExtendedTests
