||| EVM RPC Candid Encoding
|||
||| Type-safe encoding for EVM RPC canister requests.
||| Replaces the hardcoded C implementation in canister_entry.c
|||
||| Request signature:
|||   request : (RpcService, json : text, maxResponseBytes : nat64) -> (RequestResult)
|||
||| Where:
|||   RpcService = variant { EthMainnet : ServiceProvider; EthSepolia : ...; ... }
|||   ServiceProvider = variant { Alchemy; Ankr; BlockPi; Cloudflare; PublicNode; Llama }
module Candid.EvmRpc

import Candid.Leb128
import Candid.Encoder
import Candid.Chain
import Candid.Hash
import Data.Bits
import Data.List

%default total

-- =============================================================================
-- ServiceProvider Type Definition (Type 0)
-- =============================================================================

||| Build ServiceProvider variant type definition
||| All providers have null payload (type -1)
serviceProviderTypedef : List Bits8
serviceProviderTypedef =
  let fields = map (\p => variantField (providerCandidName p) (-1)) providersSortedByHash
  in encodeVariantType fields

-- =============================================================================
-- RpcService Type Definition (Type 1)
-- =============================================================================

||| Build RpcService variant type definition
||| Each chain references type 0 (ServiceProvider)
rpcServiceTypedef : List Bits8
rpcServiceTypedef =
  let fields = map (\c => variantField (chainCandidName c) 0) chainsSortedByHash
  in encodeVariantType fields

-- =============================================================================
-- EVM RPC Request Encoding
-- =============================================================================

||| Encode an EVM RPC request
|||
||| @ service  The RPC service (chain + provider)
||| @ jsonRpc  The JSON-RPC request body
||| @ maxBytes Maximum response size (typically 2000)
public export
encodeEvmRpcRequest : RpcService -> String -> Bits64 -> List Bits8
encodeEvmRpcRequest service jsonRpc maxBytes =
  let -- Type table: 2 types (ServiceProvider, RpcService)
      typeTable = [serviceProviderTypedef, rpcServiceTypedef]

      -- Argument types: (type 1 = RpcService, -15 = text, -8 = nat64)
      argTypes = [1, -15, -8]

      -- Values:
      -- 1. RpcService variant: chain_index + provider_index
      chainIdx = encodeNat (chainIndex service.chain)
      providerIdx = encodeNat (providerIndex service.provider)

      -- 2. Text: JSON-RPC body
      jsonBytes = encodeText jsonRpc

      -- 3. Nat64: max response bytes
      maxBytesVal = encodeNat64 maxBytes

      values = chainIdx ++ providerIdx ++ jsonBytes ++ maxBytesVal

  in encodeDIDL $ MkDIDL typeTable argTypes values

-- =============================================================================
-- Convenience Functions
-- =============================================================================

||| Encode EVM RPC request using chain ID (for compatibility with existing code)
||| Returns Nothing if chain ID is unknown
public export
encodeEvmRpcRequestByChainId : Int32 -> ServiceProvider -> String -> Bits64 -> Maybe (List Bits8)
encodeEvmRpcRequestByChainId chainId provider jsonRpc maxBytes = do
  chain <- fromChainId chainId
  pure $ encodeEvmRpcRequest (MkRpcService chain provider) jsonRpc maxBytes

||| Encode EVM RPC request with PublicNode (default provider)
public export
encodeEvmRpcRequestPublicNode : Chain -> String -> Bits64 -> List Bits8
encodeEvmRpcRequestPublicNode chain jsonRpc maxBytes =
  encodeEvmRpcRequest (MkRpcService chain PublicNode) jsonRpc maxBytes

-- =============================================================================
-- Specific Chain Helpers
-- =============================================================================

||| Encode Ethereum Mainnet request
public export
encodeEthMainnetRequest : String -> Bits64 -> List Bits8
encodeEthMainnetRequest = encodeEvmRpcRequestPublicNode EthMainnet

||| Encode Ethereum Sepolia (testnet) request
public export
encodeEthSepoliaRequest : String -> Bits64 -> List Bits8
encodeEthSepoliaRequest = encodeEvmRpcRequestPublicNode EthSepolia

||| Encode Base Mainnet request
public export
encodeBaseRequest : String -> Bits64 -> List Bits8
encodeBaseRequest = encodeEvmRpcRequestPublicNode BaseMainnet

||| Encode Arbitrum One request
public export
encodeArbitrumRequest : String -> Bits64 -> List Bits8
encodeArbitrumRequest = encodeEvmRpcRequestPublicNode ArbitrumOne

-- =============================================================================
-- Debug: Show encoded request
-- =============================================================================

||| Show EVM RPC request as hex dump (for debugging)
public export
showEvmRpcRequest : RpcService -> String -> Bits64 -> String
showEvmRpcRequest service jsonRpc maxBytes =
  "EVM RPC Request:\n" ++
  "  Chain: " ++ show service.chain ++ " (idx=" ++ show (chainIndex service.chain) ++ ")\n" ++
  "  Provider: " ++ show service.provider ++ " (idx=" ++ show (providerIndex service.provider) ++ ")\n" ++
  "  JSON: " ++ jsonRpc ++ "\n" ++
  "  MaxBytes: " ++ show maxBytes ++ "\n" ++
  "  Encoded: " ++ showBytes (encodeEvmRpcRequest service jsonRpc maxBytes)
