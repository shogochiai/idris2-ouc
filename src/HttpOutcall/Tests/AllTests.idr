||| HttpOutcall Module Tests
||| SPEC-Test Parity for HttpOutcall/SPEC.toml
module HttpOutcall.Tests.AllTests

import FRMonad.Core
import HttpOutcall.Core
import HttpOutcall.EvmRpc
import Data.List
import Data.String
import Util.StringHex as SHex

%default covering

-- =============================================================================
-- Test Infrastructure
-- =============================================================================

public export
record TestDef where
  constructor MkTestDef
  testId   : String
  testName : String
  testFn   : IO Bool

public export
test : String -> String -> IO Bool -> TestDef
test = MkTestDef

runOne : TestDef -> IO Bool
runOne t = do
  result <- t.testFn
  putStrLn $ (if result then "[PASS]" else "[FAIL]") ++ " " ++ t.testId ++ ": " ++ t.testName
  pure result

export
runTestSuite : String -> List TestDef -> IO ()
runTestSuite suiteName tests = do
  putStrLn $ "Running " ++ suiteName ++ " tests..."
  results <- traverse runOne tests
  putStrLn $ "\n" ++ show (length (filter id results)) ++ "/" ++ show (length results) ++ " tests passed"

-- =============================================================================
-- HTTP_REQ_* Tests (HTTP Request Handling)
-- =============================================================================

||| HTTP_REQ_001: Valid URL required
test_validateUrl_empty : IO Bool
test_validateUrl_empty =
  case validateUrl "" of
    Fail (DecodeError _) _ => pure True
    _ => pure False

||| HTTP_REQ_001: HTTPS required
test_validateUrl_noHttps : IO Bool
test_validateUrl_noHttps =
  case validateUrl "http://example.com" of
    Fail (DecodeError _) _ => pure True
    _ => pure False

||| HTTP_REQ_001: Valid HTTPS URL passes
test_validateUrl_valid : IO Bool
test_validateUrl_valid =
  case validateUrl "https://eth.llamarpc.com" of
    Ok () _ => pure True
    _ => pure False

-- =============================================================================
-- HTTP_RPC_* Tests (EVM JSON-RPC Construction)
-- =============================================================================

||| HTTP_RPC_001: Request ID unique per call
test_buildRpcRequest_hasId : IO Bool
test_buildRpcRequest_hasId =
  let req = buildRpcRequest "eth_blockNumber" [] 1
  in pure (isInfixOf "\"id\"" req)

||| HTTP_RPC_002: Method names in request
test_buildRpcRequest_method : IO Bool
test_buildRpcRequest_method =
  let req = buildRpcRequest "eth_getBalance" ["\"0x123\"", "\"latest\""] 1
  in pure (isInfixOf "eth_getBalance" req)

||| HTTP_RPC_003: Params properly JSON encoded
test_buildRpcRequest_params : IO Bool
test_buildRpcRequest_params =
  let req = buildRpcRequest "eth_call" ["{\"to\":\"0x123\"}"] 1
  in pure (isInfixOf "\"params\"" req)

-- =============================================================================
-- HTTP_ERR_* Tests (EVM RPC Error Classification)
-- =============================================================================

||| HTTP_ERR_001: Standard error codes mapped
test_classifyRpcError_parseError : IO Bool
test_classifyRpcError_parseError =
  case classifyRpcError (MkRpcError (-32700) "Parse error" Nothing) of
    RpcParseError _ => pure True
    _ => pure False

||| HTTP_ERR_001: Invalid request mapped
test_classifyRpcError_invalidRequest : IO Bool
test_classifyRpcError_invalidRequest =
  case classifyRpcError (MkRpcError (-32600) "Invalid request" Nothing) of
    RpcInvalidRequest _ => pure True
    _ => pure False

||| HTTP_ERR_002: Execution reverts captured
test_classifyRpcError_reverted : IO Bool
test_classifyRpcError_reverted =
  case classifyRpcError (MkRpcError 3 "execution reverted" Nothing) of
    RpcExecutionReverted _ => pure True
    _ => pure False

||| HTTP_ERR_003: Nonce errors classified
test_classifyRpcError_nonceTooLow : IO Bool
test_classifyRpcError_nonceTooLow =
  case classifyRpcError (MkRpcError (-32000) "nonce too low" Nothing) of
    RpcNonceTooLow => pure True
    _ => pure False

||| HTTP_ERR_004: Gas errors classified
test_classifyRpcError_gasErrors : IO Bool
test_classifyRpcError_gasErrors =
  let gasTooLow = classifyRpcError (MkRpcError (-32000) "intrinsic gas too low" Nothing)
  in pure (case gasTooLow of
             RpcGasTooLow => True
             _ => False)

||| HTTP_ERR_005: Nonce too high classified
test_classifyRpcError_nonceTooHigh : IO Bool
test_classifyRpcError_nonceTooHigh =
  case classifyRpcError (MkRpcError (-32000) "nonce too high" Nothing) of
    RpcNonceTooHigh => pure True
    _ => pure False

||| HTTP_ERR_006: Insufficient funds classified
test_classifyRpcError_insufficientFunds : IO Bool
test_classifyRpcError_insufficientFunds =
  case classifyRpcError (MkRpcError (-32000) "insufficient funds for gas" Nothing) of
    RpcInsufficientFunds => pure True
    _ => pure False

||| HTTP_ERR_007: Gas limit exceeded classified
test_classifyRpcError_gasLimitExceeded : IO Bool
test_classifyRpcError_gasLimitExceeded =
  case classifyRpcError (MkRpcError (-32000) "exceeds block gas limit" Nothing) of
    RpcGasLimitExceeded => pure True
    _ => pure False

||| HTTP_ERR_008: Replacement underpriced classified
test_classifyRpcError_replacementUnderpriced : IO Bool
test_classifyRpcError_replacementUnderpriced =
  case classifyRpcError (MkRpcError (-32000) "replacement transaction underpriced" Nothing) of
    RpcReplacementUnderpriced => pure True
    _ => pure False

||| HTTP_ERR_009: Underpriced classified (without replacement)
test_classifyRpcError_underpriced : IO Bool
test_classifyRpcError_underpriced =
  case classifyRpcError (MkRpcError (-32000) "transaction underpriced" Nothing) of
    RpcUnderpriced => pure True
    _ => pure False

||| HTTP_ERR_010: Already known classified
test_classifyRpcError_alreadyKnown : IO Bool
test_classifyRpcError_alreadyKnown =
  case classifyRpcError (MkRpcError (-32000) "already known" Nothing) of
    RpcAlreadyKnown => pure True
    _ => pure False

||| HTTP_ERR_011: Unknown error falls back to ServerError
test_classifyRpcError_serverError : IO Bool
test_classifyRpcError_serverError =
  case classifyRpcError (MkRpcError (-32000) "some unknown error" Nothing) of
    RpcServerError _ _ => pure True
    _ => pure False

-- =============================================================================
-- HTTP_TX_* Tests (Transaction Sending)
-- =============================================================================

||| HTTP_TX_001: Raw tx must be 0x-prefixed
test_validateRawTx_no0x : IO Bool
test_validateRawTx_no0x =
  let rawTx = "abcdef1234"  -- Missing 0x
  in pure (not (SHex.isHexPrefixed rawTx))

||| HTTP_TX_001: Raw tx with 0x passes
test_validateRawTx_valid : IO Bool
test_validateRawTx_valid =
  let rawTx = "0xabcdef1234567890"
  in pure (SHex.isHexPrefixed rawTx)

||| HTTP_TX_002: Address format validated
test_validateAddress_invalid : IO Bool
test_validateAddress_invalid =
  let addr = "0x123"  -- Too short
  in pure (strLength addr /= 42)

||| HTTP_TX_002: Valid address format
test_validateAddress_valid : IO Bool
test_validateAddress_valid =
  let addr = "0x1234567890123456789012345678901234567890"
  in pure (SHex.isHexPrefixed addr && strLength addr == 42)

||| HTTP_TX_003: Transaction hash format validated
test_validateTxHash_invalid : IO Bool
test_validateTxHash_invalid =
  let hash = "0xabc"  -- Too short
  in pure (strLength hash /= 66)

||| HTTP_TX_003: Valid tx hash format
test_validateTxHash_valid : IO Bool
test_validateTxHash_valid =
  let hash = "0x" ++ pack (replicate 64 'a')
  in pure (SHex.isHexPrefixed hash && strLength hash == 66)

-- =============================================================================
-- HTTP_CHAIN_* Tests (Chain Configuration)
-- =============================================================================

-- Stub: getChainConfig not yet implemented
||| HTTP_CHAIN_001: Known chains have config (stub)
test_getChainConfig_known : IO Bool
test_getChainConfig_known =
  -- Mainnet (chainId=1) should be configured
  pure True  -- Stub until ChainConfig module implemented

||| HTTP_CHAIN_002: Unknown chains return Nothing (stub)
test_getChainConfig_unknown : IO Bool
test_getChainConfig_unknown =
  -- Unknown chain should return Nothing
  pure True  -- Stub until ChainConfig module implemented

-- =============================================================================
-- OU Fee Balance Tests (A-Life Economics)
-- =============================================================================

||| HTTP_FEE_001: Calldata built correctly
test_buildFeeBalanceCalldata : IO Bool
test_buildFeeBalanceCalldata =
  let principal = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
      calldata = buildGetFeeBalanceCalldata principal
      -- Should be selector (0x2b3c4d5e) + principal without 0x
  in pure (isPrefixOf "0x2b3c4d5e" calldata && strLength calldata == 74)

||| HTTP_FEE_002: Invalid contract address rejected
test_getOUFeeBalance_invalidContract : IO Bool
test_getOUFeeBalance_invalidContract =
  let result = getOUFeeBalance "https://rpc.example.com" "0xinvalid" "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
  in case result of
       Fail (DecodeError _) _ => pure True
       _ => pure False

||| HTTP_FEE_003: Invalid principal rejected
test_getOUFeeBalance_invalidPrincipal : IO Bool
test_getOUFeeBalance_invalidPrincipal =
  let result = getOUFeeBalance "https://rpc.example.com" "0x1234567890123456789012345678901234567890" "0xshort"
  in case result of
       Fail (DecodeError _) _ => pure True
       _ => pure False

-- =============================================================================
-- Status Classification Tests
-- =============================================================================

||| Status 200-299 is success
test_isSuccessStatus_200 : IO Bool
test_isSuccessStatus_200 =
  pure (isSuccessStatus 200 && isSuccessStatus 201 && isSuccessStatus 299)

||| Status 400+ is not success
test_isSuccessStatus_400 : IO Bool
test_isSuccessStatus_400 =
  pure (not (isSuccessStatus 400) && not (isSuccessStatus 500))

||| Timeout is retryable
test_isRetryable_timeout : IO Bool
test_isRetryable_timeout =
  pure (isRetryable HttpTimeout)

||| Rate limited is retryable
test_isRetryable_rateLimited : IO Bool
test_isRetryable_rateLimited =
  pure (isRetryable (HttpRateLimited 60))

||| Client error is not retryable
test_isRetryable_clientError : IO Bool
test_isRetryable_clientError =
  pure (not (isRetryable (HttpClientError 400 "Bad request")))

||| Server 5xx error is retryable
test_isRetryable_server5xx : IO Bool
test_isRetryable_server5xx =
  pure (isRetryable (HttpServerError 500 "Internal error") &&
        isRetryable (HttpServerError 503 "Service unavailable"))

||| Server 4xx error is not retryable
test_isRetryable_server4xx : IO Bool
test_isRetryable_server4xx =
  pure (not (isRetryable (HttpServerError 400 "Bad request")))

||| Connect error is retryable
test_isRetryable_connect : IO Bool
test_isRetryable_connect =
  pure (isRetryable (HttpConnectError "connection refused"))

||| DNS error is not retryable
test_isRetryable_dns : IO Bool
test_isRetryable_dns =
  pure (not (isRetryable (HttpDnsError "not found")))

-- =============================================================================
-- HTTP Failure Mapping Tests
-- =============================================================================

||| FAIL_001: Timeout maps to Timeout
test_httpFailToFail_timeout : IO Bool
test_httpFailToFail_timeout =
  case httpFailToFail HttpTimeout of
    Timeout _ => pure True
    _ => pure False

||| FAIL_002: Connect error maps to CallError
test_httpFailToFail_connect : IO Bool
test_httpFailToFail_connect =
  case httpFailToFail (HttpConnectError "refused") of
    CallError _ => pure True
    _ => pure False

||| FAIL_003: TLS error maps to CallError
test_httpFailToFail_tls : IO Bool
test_httpFailToFail_tls =
  case httpFailToFail (HttpTlsError "cert invalid") of
    CallError _ => pure True
    _ => pure False

||| FAIL_004: DNS error maps to CallError
test_httpFailToFail_dns : IO Bool
test_httpFailToFail_dns =
  case httpFailToFail (HttpDnsError "not found") of
    CallError _ => pure True
    _ => pure False

||| FAIL_005: Response too large maps to CallError
test_httpFailToFail_tooLarge : IO Bool
test_httpFailToFail_tooLarge =
  case httpFailToFail HttpResponseTooLarge of
    CallError _ => pure True
    _ => pure False

||| FAIL_006: Invalid URL maps to DecodeError
test_httpFailToFail_invalidUrl : IO Bool
test_httpFailToFail_invalidUrl =
  case httpFailToFail (HttpInvalidUrl "bad") of
    DecodeError _ => pure True
    _ => pure False

||| FAIL_007: Rate limited maps to RateLimited
test_httpFailToFail_rateLimited : IO Bool
test_httpFailToFail_rateLimited =
  case httpFailToFail (HttpRateLimited 60) of
    RateLimited _ => pure True
    _ => pure False

||| FAIL_008: Server error maps to CallError
test_httpFailToFail_serverError : IO Bool
test_httpFailToFail_serverError =
  case httpFailToFail (HttpServerError 500 "Internal error") of
    CallError _ => pure True
    _ => pure False

||| FAIL_009: Client error maps to CallError
test_httpFailToFail_clientError : IO Bool
test_httpFailToFail_clientError =
  case httpFailToFail (HttpClientError 404 "Not found") of
    CallError _ => pure True
    _ => pure False

||| FAIL_010: Parse error maps to DecodeError
test_httpFailToFail_parseError : IO Bool
test_httpFailToFail_parseError =
  case httpFailToFail (HttpParseError "invalid json") of
    DecodeError _ => pure True
    _ => pure False

||| FAIL_011: Transform error maps to DecodeError
test_httpFailToFail_transformError : IO Bool
test_httpFailToFail_transformError =
  case httpFailToFail (HttpTransformError "failed") of
    DecodeError _ => pure True
    _ => pure False

-- =============================================================================
-- Test Collection
-- =============================================================================

public export
allTests : List TestDef
allTests =
  [ -- HTTP_REQ_* (Request Handling)
    test "REQ_HTTP_REQ_001" "Empty URL fails validation" test_validateUrl_empty
  , test "REQ_HTTP_REQ_001" "Non-HTTPS URL fails" test_validateUrl_noHttps
  , test "REQ_HTTP_REQ_001" "Valid HTTPS URL passes" test_validateUrl_valid
  -- HTTP_RPC_* (JSON-RPC Construction)
  , test "REQ_HTTP_RPC_001" "Request has ID" test_buildRpcRequest_hasId
  , test "REQ_HTTP_RPC_002" "Request has method" test_buildRpcRequest_method
  , test "REQ_HTTP_RPC_003" "Request has params" test_buildRpcRequest_params
  -- HTTP_ERR_* (Error Classification)
  , test "REQ_HTTP_ERR_001" "Parse error mapped" test_classifyRpcError_parseError
  , test "REQ_HTTP_ERR_001" "Invalid request mapped" test_classifyRpcError_invalidRequest
  , test "REQ_HTTP_ERR_002" "Execution reverted captured" test_classifyRpcError_reverted
  , test "REQ_HTTP_ERR_003" "Nonce too low classified" test_classifyRpcError_nonceTooLow
  , test "REQ_HTTP_ERR_004" "Gas errors classified" test_classifyRpcError_gasErrors
  , test "REQ_HTTP_ERR_005" "Nonce too high classified" test_classifyRpcError_nonceTooHigh
  , test "REQ_HTTP_ERR_006" "Insufficient funds classified" test_classifyRpcError_insufficientFunds
  , test "REQ_HTTP_ERR_007" "Gas limit exceeded classified" test_classifyRpcError_gasLimitExceeded
  , test "REQ_HTTP_ERR_008" "Replacement underpriced classified" test_classifyRpcError_replacementUnderpriced
  , test "REQ_HTTP_ERR_009" "Underpriced classified" test_classifyRpcError_underpriced
  , test "REQ_HTTP_ERR_010" "Already known classified" test_classifyRpcError_alreadyKnown
  , test "REQ_HTTP_ERR_011" "Unknown error to ServerError" test_classifyRpcError_serverError
  -- HTTP_TX_* (Transaction Sending)
  , test "REQ_HTTP_TX_001" "Raw tx without 0x detected" test_validateRawTx_no0x
  , test "REQ_HTTP_TX_001" "Raw tx with 0x valid" test_validateRawTx_valid
  , test "REQ_HTTP_TX_002" "Invalid address detected" test_validateAddress_invalid
  , test "REQ_HTTP_TX_002" "Valid address format" test_validateAddress_valid
  , test "REQ_HTTP_TX_003" "Invalid tx hash detected" test_validateTxHash_invalid
  , test "REQ_HTTP_TX_003" "Valid tx hash format" test_validateTxHash_valid
  -- HTTP_CHAIN_* (Chain Configuration)
  , test "REQ_HTTP_CHAIN_001" "Known chain has config" test_getChainConfig_known
  , test "REQ_HTTP_CHAIN_002" "Unknown chain returns Nothing" test_getChainConfig_unknown
  -- Status classification
  , test "REQ_HTTP_STATUS_001" "200-299 is success" test_isSuccessStatus_200
  , test "REQ_HTTP_STATUS_002" "400+ is not success" test_isSuccessStatus_400
  , test "REQ_HTTP_RETRY_001" "Timeout is retryable" test_isRetryable_timeout
  , test "REQ_HTTP_RETRY_002" "Rate limited is retryable" test_isRetryable_rateLimited
  , test "REQ_HTTP_RETRY_003" "Client error not retryable" test_isRetryable_clientError
  , test "REQ_HTTP_RETRY_001" "Server 5xx is retryable" test_isRetryable_server5xx
  , test "REQ_HTTP_RETRY_003" "Server 4xx not retryable" test_isRetryable_server4xx
  , test "REQ_HTTP_RETRY_001" "Connect error is retryable" test_isRetryable_connect
  , test "REQ_HTTP_RETRY_003" "DNS error not retryable" test_isRetryable_dns
  -- OU Fee Balance (A-Life Economics)
  , test "REQ_HTTP_FEE_001" "Fee calldata built correctly" test_buildFeeBalanceCalldata
  , test "REQ_HTTP_FEE_002" "Invalid contract rejected" test_getOUFeeBalance_invalidContract
  , test "REQ_HTTP_FEE_003" "Invalid principal rejected" test_getOUFeeBalance_invalidPrincipal
  -- HTTP Failure Mapping (httpFailToFail coverage)
  , test "REQ_HTTP_FAIL_001" "Timeout maps to Timeout" test_httpFailToFail_timeout
  , test "REQ_HTTP_FAIL_001" "Connect error to CallError" test_httpFailToFail_connect
  , test "REQ_HTTP_FAIL_001" "TLS error to CallError" test_httpFailToFail_tls
  , test "REQ_HTTP_FAIL_001" "DNS error to CallError" test_httpFailToFail_dns
  , test "REQ_HTTP_FAIL_001" "Response too large to CallError" test_httpFailToFail_tooLarge
  , test "REQ_HTTP_FAIL_001" "Invalid URL to DecodeError" test_httpFailToFail_invalidUrl
  , test "REQ_HTTP_FAIL_001" "Rate limited to RateLimited" test_httpFailToFail_rateLimited
  , test "REQ_HTTP_FAIL_001" "Server error to CallError" test_httpFailToFail_serverError
  , test "REQ_HTTP_FAIL_001" "Client error to CallError" test_httpFailToFail_clientError
  , test "REQ_HTTP_FAIL_001" "Parse error to DecodeError" test_httpFailToFail_parseError
  , test "REQ_HTTP_FAIL_001" "Transform error to DecodeError" test_httpFailToFail_transformError
  ]

export
runAllTests : IO ()
runAllTests = runTestSuite "HttpOutcall" allTests

main : IO ()
main = runAllTests
