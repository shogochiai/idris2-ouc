||| EVM JSON-RPC Module
|||
||| Constructs and parses Ethereum JSON-RPC requests/responses.
module HttpOutcall.EvmRpc

import FRMonad.Core
import HttpOutcall.Core
import Data.List
import Data.String
import Data.Maybe
import Util.StringHex
import Util.StringCase

%default total

-- =============================================================================
-- JSON-RPC Types
-- =============================================================================

||| JSON-RPC request ID
public export
RpcId : Type
RpcId = Nat

||| JSON-RPC error structure
public export
record RpcError where
  constructor MkRpcError
  code    : Int
  message : String
  rpcData : Maybe String

public export
Show RpcError where
  show e = "RpcError(" ++ show e.code ++ "): " ++ e.message

||| EVM-specific RPC failure classification
public export
data EvmRpcFail
  = RpcParseError String
  | RpcInvalidRequest String
  | RpcMethodNotFound String
  | RpcInvalidParams String
  | RpcInternalError String
  | RpcServerError Int String
  | RpcExecutionReverted String   -- EVM revert with reason
  | RpcNonceTooLow
  | RpcNonceTooHigh
  | RpcInsufficientFunds
  | RpcGasTooLow
  | RpcGasTooHigh
  | RpcUnderpriced
  | RpcAlreadyKnown               -- Tx already in mempool
  | RpcReplacementUnderpriced
  | RpcGasLimitExceeded

public export
Show EvmRpcFail where
  show (RpcParseError s)        = "ParseError: " ++ s
  show (RpcInvalidRequest s)    = "InvalidRequest: " ++ s
  show (RpcMethodNotFound s)    = "MethodNotFound: " ++ s
  show (RpcInvalidParams s)     = "InvalidParams: " ++ s
  show (RpcInternalError s)     = "InternalError: " ++ s
  show (RpcServerError c s)     = "ServerError(" ++ show c ++ "): " ++ s
  show (RpcExecutionReverted s) = "Reverted: " ++ s
  show RpcNonceTooLow           = "NonceTooLow"
  show RpcNonceTooHigh          = "NonceTooHigh"
  show RpcInsufficientFunds     = "InsufficientFunds"
  show RpcGasTooLow             = "GasTooLow"
  show RpcGasTooHigh            = "GasTooHigh"
  show RpcUnderpriced           = "Underpriced"
  show RpcAlreadyKnown          = "AlreadyKnown"
  show RpcReplacementUnderpriced = "ReplacementUnderpriced"
  show RpcGasLimitExceeded      = "GasLimitExceeded"

-- =============================================================================
-- Error Classification
-- =============================================================================

||| Classify error message to specific failure type
classifyByMessage : String -> Int -> EvmRpcFail
classifyByMessage msg code =
  let msgLower = strToLower msg
  in if isInfixOf "nonce too low" msgLower then RpcNonceTooLow
     else if isInfixOf "nonce too high" msgLower then RpcNonceTooHigh
     else if isInfixOf "insufficient funds" msgLower then RpcInsufficientFunds
     else if isInfixOf "intrinsic gas too low" msgLower then RpcGasTooLow
     else if isInfixOf "gas limit" msgLower then RpcGasLimitExceeded
     else if isInfixOf "underpriced" msgLower && isInfixOf "replacement" msgLower
       then RpcReplacementUnderpriced
     else if isInfixOf "underpriced" msgLower then RpcUnderpriced
     else if isInfixOf "already known" msgLower then RpcAlreadyKnown
     else if isInfixOf "execution reverted" msgLower then RpcExecutionReverted msg
     else RpcServerError code msg

||| Convert RpcError code to EvmRpcFail
public export
classifyRpcError : RpcError -> EvmRpcFail
classifyRpcError err =
  case err.code of
    (-32700) => RpcParseError err.message
    (-32600) => RpcInvalidRequest err.message
    (-32601) => RpcMethodNotFound err.message
    (-32602) => RpcInvalidParams err.message
    (-32603) => RpcInternalError err.message
    3        => RpcExecutionReverted (fromMaybe err.message err.rpcData)
    _        => if err.code >= (-32099) && err.code <= (-32000)
                  then RpcServerError (cast err.code) err.message
                  else classifyByMessage err.message (cast err.code)

||| Convert EvmRpcFail to IcpFail
public export
evmRpcFailToIcpFail : EvmRpcFail -> IcpFail
evmRpcFailToIcpFail (RpcExecutionReverted s) = CallError ("Reverted: " ++ s)
evmRpcFailToIcpFail RpcNonceTooLow           = Conflict "Nonce too low"
evmRpcFailToIcpFail RpcNonceTooHigh          = Conflict "Nonce too high"
evmRpcFailToIcpFail RpcInsufficientFunds     = Unauthorized "Insufficient funds"
evmRpcFailToIcpFail RpcUnderpriced           = Conflict "Transaction underpriced"
evmRpcFailToIcpFail RpcAlreadyKnown          = Conflict "Transaction already known"
evmRpcFailToIcpFail RpcReplacementUnderpriced = Conflict "Replacement transaction underpriced"
evmRpcFailToIcpFail RpcGasLimitExceeded      = CallError "Gas limit exceeded"
evmRpcFailToIcpFail (RpcParseError s)        = DecodeError s
evmRpcFailToIcpFail (RpcInvalidRequest s)    = DecodeError s
evmRpcFailToIcpFail (RpcMethodNotFound s)    = NotFound s
evmRpcFailToIcpFail (RpcInvalidParams s)     = DecodeError s
evmRpcFailToIcpFail other                    = CallError (show other)

-- =============================================================================
-- JSON-RPC Request Building
-- =============================================================================

||| Escape string for JSON
escapeJson : String -> String
escapeJson s = s  -- Simplified; real impl needs proper escaping

||| Build JSON-RPC request body
public export
buildRpcRequest : String -> List String -> RpcId -> String
buildRpcRequest method params reqId =
  "{\"jsonrpc\":\"2.0\",\"method\":\"" ++ escapeJson method ++
  "\",\"params\":[" ++ joinBy "," params ++
  "],\"id\":" ++ show reqId ++ "}"

||| Build eth_sendRawTransaction request
public export
buildSendRawTx : String -> RpcId -> String
buildSendRawTx rawTxHex reqId =
  buildRpcRequest "eth_sendRawTransaction" ["\"" ++ rawTxHex ++ "\""] reqId

||| Build eth_call request
public export
buildEthCall : String -> String -> String -> RpcId -> String
buildEthCall toAddr calldata blockTag reqId =
  let callObj = "{\"to\":\"" ++ toAddr ++ "\",\"data\":\"" ++ calldata ++ "\"}"
  in buildRpcRequest "eth_call" [callObj, "\"" ++ blockTag ++ "\""] reqId

||| Build eth_estimateGas request
public export
buildEstimateGas : String -> String -> String -> RpcId -> String
buildEstimateGas fromAddr toAddr calldata reqId =
  let callObj = "{\"from\":\"" ++ fromAddr ++ "\",\"to\":\"" ++ toAddr ++ "\",\"data\":\"" ++ calldata ++ "\"}"
  in buildRpcRequest "eth_estimateGas" [callObj] reqId

||| Build eth_getTransactionReceipt request
public export
buildGetReceipt : String -> RpcId -> String
buildGetReceipt txHash reqId =
  buildRpcRequest "eth_getTransactionReceipt" ["\"" ++ txHash ++ "\""] reqId

||| Build eth_getTransactionCount (for nonce)
public export
buildGetNonce : String -> String -> RpcId -> String
buildGetNonce address blockTag reqId =
  buildRpcRequest "eth_getTransactionCount" ["\"" ++ address ++ "\"", "\"" ++ blockTag ++ "\""] reqId

||| Build eth_gasPrice request
public export
buildGasPrice : RpcId -> String
buildGasPrice reqId =
  buildRpcRequest "eth_gasPrice" [] reqId

||| Build eth_chainId request
public export
buildChainId : RpcId -> String
buildChainId reqId =
  buildRpcRequest "eth_chainId" [] reqId

||| Build eth_blockNumber request
public export
buildBlockNumber : RpcId -> String
buildBlockNumber reqId =
  buildRpcRequest "eth_blockNumber" [] reqId

-- =============================================================================
-- Response Parsing
-- =============================================================================

||| Transaction receipt structure
public export
record TxReceiptData where
  constructor MkTxReceiptData
  transactionHash   : String
  blockNumber       : Nat
  status            : Bool       -- true = success, false = reverted
  gasUsed           : Nat
  contractAddress   : Maybe String
  logs              : List String  -- Simplified

public export
Show TxReceiptData where
  show r = "TxReceipt{hash=" ++ r.transactionHash ++
           ", block=" ++ show r.blockNumber ++
           ", status=" ++ show r.status ++ "}"

||| Parse hex string to Nat (simplified)
parseHexNat : String -> Maybe Nat
parseHexNat s = Just 0  -- Stub; real implementation would parse hex

-- =============================================================================
-- EVM RPC Operations (FRC-compliant)
-- =============================================================================

||| Send raw transaction via RPC
public export
sendRawTransaction :
  String ->           -- RPC URL
  String ->           -- Raw transaction hex (0x-prefixed)
  FR String           -- Returns txHash
sendRawTransaction rpcUrl rawTx = do
  -- Validate inputs
  if not (isHexPrefixed rawTx)
    then fail Update "sendRawTransaction" "Invalid tx format"
              (DecodeError "Raw transaction must be 0x-prefixed")
    else
      let reqBody = buildSendRawTx rawTx 1
          httpReq = buildJsonRpcRequest rpcUrl reqBody
      in -- Would call httpRequest here
         fail HttpRequest "sendRawTransaction"
              ("Sending to " ++ rpcUrl)
              (Internal "Full implementation requires HTTP execution")

||| Call contract (read-only)
public export
ethCall :
  String ->           -- RPC URL
  String ->           -- Contract address
  String ->           -- Calldata
  FR String           -- Returns result data
ethCall rpcUrl toAddr calldata = do
  if not (isHexPrefixed toAddr) || length toAddr /= 42
    then fail Query "ethCall" "Invalid address"
              (DecodeError "Address must be 0x + 40 hex chars")
    else
      let reqBody = buildEthCall toAddr calldata "latest" 1
          httpReq = buildJsonRpcRequest rpcUrl reqBody
      in fail HttpRequest "ethCall"
              ("Calling " ++ toAddr)
              (Internal "Full implementation requires HTTP execution")

||| Get transaction receipt
public export
getTransactionReceipt :
  String ->           -- RPC URL
  String ->           -- Transaction hash
  FR (Maybe TxReceiptData)
getTransactionReceipt rpcUrl txHash = do
  if not (isHexPrefixed txHash) || length txHash /= 66
    then fail Query "getTransactionReceipt" "Invalid tx hash"
              (DecodeError "Tx hash must be 0x + 64 hex chars")
    else
      let reqBody = buildGetReceipt txHash 1
          httpReq = buildJsonRpcRequest rpcUrl reqBody
      in fail HttpRequest "getTransactionReceipt"
              ("Getting receipt for " ++ txHash)
              (Internal "Full implementation requires HTTP execution")

||| Get account nonce
public export
getNonce :
  String ->           -- RPC URL
  String ->           -- Address
  FR Nat
getNonce rpcUrl address = do
  if not (isHexPrefixed address) || length address /= 42
    then fail Query "getNonce" "Invalid address"
              (DecodeError "Address must be 0x + 40 hex chars")
    else
      let reqBody = buildGetNonce address "pending" 1
          httpReq = buildJsonRpcRequest rpcUrl reqBody
      in fail HttpRequest "getNonce"
              ("Getting nonce for " ++ address)
              (Internal "Full implementation requires HTTP execution")

||| Get current gas price
public export
getGasPrice :
  String ->           -- RPC URL
  FR Nat              -- Gas price in wei
getGasPrice rpcUrl =
  let reqBody = buildGasPrice 1
      httpReq = buildJsonRpcRequest rpcUrl reqBody
  in fail HttpRequest "getGasPrice"
          ("Getting gas price from " ++ rpcUrl)
          (Internal "Full implementation requires HTTP execution")

||| Estimate gas for transaction
public export
estimateGas :
  String ->           -- RPC URL
  String ->           -- From address
  String ->           -- To address
  String ->           -- Calldata
  FR Nat              -- Estimated gas
estimateGas rpcUrl fromAddr toAddr calldata =
  let reqBody = buildEstimateGas fromAddr toAddr calldata 1
      httpReq = buildJsonRpcRequest rpcUrl reqBody
  in fail HttpRequest "estimateGas"
          ("Estimating gas for call to " ++ toAddr)
          (Internal "Full implementation requires HTTP execution")
