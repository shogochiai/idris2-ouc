||| Candid Encoding FFI
|||
||| FFI interface for writing Candid-encoded bytes to a shared buffer
||| that C code can use for IC0 calls.
module Candid.FFI

import Candid.Chain
import Candid.EvmRpc
import Data.Bits
import Data.List

%default total

-- =============================================================================
-- Low-level FFI Primitives
-- =============================================================================

||| Write a byte to the Candid buffer at index
export
%foreign "C:ouc_candid_write_byte,libic0"
prim__candidWriteByte : Int -> Int -> PrimIO ()

||| Set the total length of the Candid buffer
export
%foreign "C:ouc_candid_set_len,libic0"
prim__candidSetLen : Int -> PrimIO ()

||| Clear the Candid buffer
export
%foreign "C:ouc_candid_clear,libic0"
prim__candidClear : PrimIO ()

-- =============================================================================
-- High-level IO Wrappers
-- =============================================================================

||| Write a byte to the Candid buffer at index
export
writeCandidByte : Int -> Bits8 -> IO ()
writeCandidByte idx b = primIO $ prim__candidWriteByte idx (cast b)

||| Set the total length of the Candid buffer
export
setCandidLen : Int -> IO ()
setCandidLen len = primIO $ prim__candidSetLen len

||| Clear the Candid buffer
export
clearCandidBuf : IO ()
clearCandidBuf = primIO prim__candidClear

||| Write a list of bytes to the Candid buffer starting at offset
export
writeCandidBytes : Int -> List Bits8 -> IO ()
writeCandidBytes offset [] = pure ()
writeCandidBytes offset (b :: bs) = do
  writeCandidByte offset b
  writeCandidBytes (offset + 1) bs

||| Write a complete Candid message to the buffer
||| Returns the length of the message
export
writeCandidMessage : List Bits8 -> IO Int
writeCandidMessage bytes = do
  clearCandidBuf
  writeCandidBytes 0 bytes
  let len = cast (length bytes)
  setCandidLen len
  pure len

-- =============================================================================
-- EVM RPC Request Writer
-- =============================================================================

||| Write EVM RPC request to the Candid buffer
||| Returns the length of the encoded message
export
writeEvmRpcRequest : RpcService -> String -> Bits64 -> IO Int
writeEvmRpcRequest service jsonRpc maxBytes = do
  let bytes = encodeEvmRpcRequest service jsonRpc maxBytes
  writeCandidMessage bytes

||| Write EVM RPC request with chain ID (for C compatibility)
||| Returns length on success, -1 if chain ID is unknown
export
writeEvmRpcRequestByChainId : Int32 -> String -> Bits64 -> IO Int
writeEvmRpcRequestByChainId chainId jsonRpc maxBytes =
  case fromChainId chainId of
    Nothing => pure (-1)  -- Unknown chain
    Just chain => writeEvmRpcRequest (MkRpcService chain PublicNode) jsonRpc maxBytes

-- =============================================================================
-- Command Constants (for Main.idr integration)
-- =============================================================================

-- =============================================================================
-- JSON Input Buffer (read from C)
-- =============================================================================

||| Get length of JSON in buffer
export
%foreign "C:ouc_json_get_len,libic0"
prim__jsonGetLen : PrimIO Int

||| Get byte at index from JSON buffer
export
%foreign "C:ouc_json_get_byte,libic0"
prim__jsonGetByte : Int -> PrimIO Int

||| Get JSON length
export
getJsonLen : IO Int
getJsonLen = primIO prim__jsonGetLen

||| Get JSON byte at index
export
getJsonByte : Int -> IO Bits8
getJsonByte idx = do
  b <- primIO $ prim__jsonGetByte idx
  pure (cast b)

||| Read bytes from JSON buffer (helper)
partial
readJsonBytes : Int -> Int -> List Bits8 -> IO (List Bits8)
readJsonBytes idx len acc =
  if idx >= len
    then pure (reverse acc)
    else do
      b <- getJsonByte idx
      readJsonBytes (idx + 1) len (b :: acc)

||| Read JSON string from buffer
export
readJsonString : IO String
readJsonString = do
  len <- getJsonLen
  bytes <- assert_total $ readJsonBytes 0 len []
  pure (pack (map (chr . cast) bytes))

-- =============================================================================
-- Complete EVM RPC Encoding (with JSON from C buffer)
-- =============================================================================

||| Encode EVM RPC request using JSON from C buffer
||| chain_id: 1=EthMainnet, 11155111=Sepolia, 8453=Base, 42161=Arbitrum
||| max_bytes: maximum response size (e.g., 2000)
||| Returns: length of encoded Candid, or -1 on error
export
encodeEvmRpcFromBuffer : Int32 -> Bits64 -> IO Int
encodeEvmRpcFromBuffer chainId maxBytes = do
  json <- readJsonString
  case fromChainId chainId of
    Nothing => pure (-1)  -- Unknown chain
    Just chain => writeEvmRpcRequest (MkRpcService chain PublicNode) json maxBytes

-- =============================================================================
-- Command Constants (for Main.idr integration)
-- =============================================================================

||| Command ID for encoding EVM RPC request
||| Args: [0]=cmd, [1]=chainId, [2]=maxBytesLo, [3]=maxBytesHi
||| JSON is read from ouc_json_buf (set by C via ouc_c_set_json)
||| Result written to ouc_candid_buf
public export
CMD_ENCODE_EVM_RPC : Int
CMD_ENCODE_EVM_RPC = 100
