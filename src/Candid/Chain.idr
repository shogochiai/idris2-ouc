||| Chain and Service Provider Types for EVM RPC
|||
||| Type-safe representation of chains and providers.
||| Hashes and indices are derived from the Candid spec, not hardcoded.
|||
||| This replaces the magic numbers in canister_entry.c:
|||   case 8453: chain_hash = 0x71972D93; chain_idx = 1; break;
|||
||| With type-safe, derived values:
|||   chainHash Base       -- computed: 0x71972D93
|||   chainIndex Base      -- computed: 1 (sorted by hash)
module Candid.Chain

import Candid.Hash
import Data.Bits
import Data.List
import Data.Maybe

%default total

-- =============================================================================
-- Chain ADT
-- =============================================================================

||| Supported EVM chains
||| Adding a new chain here automatically updates all hash/index calculations
public export
data Chain
  = EthMainnet    -- chainId: 1
  | EthSepolia    -- chainId: 11155111 (testnet)
  | BaseMainnet   -- chainId: 8453
  | ArbitrumOne   -- chainId: 42161

public export
Eq Chain where
  EthMainnet  == EthMainnet  = True
  EthSepolia  == EthSepolia  = True
  BaseMainnet == BaseMainnet = True
  ArbitrumOne == ArbitrumOne = True
  _ == _ = False

public export
Show Chain where
  show EthMainnet  = "EthMainnet"
  show EthSepolia  = "EthSepolia"
  show BaseMainnet = "BaseMainnet"
  show ArbitrumOne = "ArbitrumOne"

||| All chains (used for sorting and index calculation)
public export
allChains : List Chain
allChains = [EthMainnet, EthSepolia, BaseMainnet, ArbitrumOne]

-- =============================================================================
-- Chain -> Candid Name (for hash calculation)
-- =============================================================================

||| Candid variant name for a chain
||| Must match exactly what's in the EVM RPC canister's .did file
public export
chainCandidName : Chain -> String
chainCandidName EthMainnet  = "EthMainnet"
chainCandidName EthSepolia  = "EthSepolia"
chainCandidName BaseMainnet = "BaseMainnet"
chainCandidName ArbitrumOne = "ArbitrumOne"

-- =============================================================================
-- Chain ID (EVM standard)
-- =============================================================================

||| EVM chain ID
public export
chainId : Chain -> Int32
chainId EthMainnet  = 1
chainId EthSepolia  = 11155111
chainId BaseMainnet = 8453
chainId ArbitrumOne = 42161

||| Parse chain ID to Chain (safe - returns Maybe)
||| Unknown chain IDs return Nothing, not a default!
public export
fromChainId : Int32 -> Maybe Chain
fromChainId 1        = Just EthMainnet
fromChainId 11155111 = Just EthSepolia
fromChainId 8453     = Just BaseMainnet
fromChainId 42161    = Just ArbitrumOne
fromChainId _        = Nothing

-- =============================================================================
-- Candid Hash (derived, not hardcoded)
-- =============================================================================

||| Candid variant hash for a chain
||| Computed from the name, not hardcoded
public export
chainHash : Chain -> Bits32
chainHash = candidHash . chainCandidName

-- =============================================================================
-- Candid Variant Index (sorted by hash)
-- =============================================================================

||| Sort chains by their Candid hash (ascending)
||| This determines the variant index in Candid encoding
public export
chainsSortedByHash : List Chain
chainsSortedByHash = sortBy (\a, b => compare (chainHash a) (chainHash b)) allChains

||| Get variant index for a chain in Candid encoding
||| Index is position in hash-sorted list (0-based)
public export
chainIndex : Chain -> Nat
chainIndex c = fromMaybe 0 (map finToNat (findIndex (== c) chainsSortedByHash))

-- =============================================================================
-- Service Provider ADT
-- =============================================================================

||| EVM RPC service providers
public export
data ServiceProvider
  = Alchemy
  | Ankr
  | BlockPi
  | Cloudflare
  | PublicNode
  | Llama

public export
Eq ServiceProvider where
  Alchemy    == Alchemy    = True
  Ankr       == Ankr       = True
  BlockPi    == BlockPi    = True
  Cloudflare == Cloudflare = True
  PublicNode == PublicNode = True
  Llama      == Llama      = True
  _ == _ = False

public export
Show ServiceProvider where
  show Alchemy    = "Alchemy"
  show Ankr       = "Ankr"
  show BlockPi    = "BlockPi"
  show Cloudflare = "Cloudflare"
  show PublicNode = "PublicNode"
  show Llama      = "Llama"

||| All service providers
public export
allProviders : List ServiceProvider
allProviders = [Alchemy, Ankr, BlockPi, Cloudflare, PublicNode, Llama]

||| Candid variant name for a provider
public export
providerCandidName : ServiceProvider -> String
providerCandidName Alchemy    = "Alchemy"
providerCandidName Ankr       = "Ankr"
providerCandidName BlockPi    = "BlockPi"
providerCandidName Cloudflare = "Cloudflare"
providerCandidName PublicNode = "PublicNode"
providerCandidName Llama      = "Llama"

||| Candid hash for a provider
public export
providerHash : ServiceProvider -> Bits32
providerHash = candidHash . providerCandidName

||| Providers sorted by hash
public export
providersSortedByHash : List ServiceProvider
providersSortedByHash = sortBy (\a, b => compare (providerHash a) (providerHash b)) allProviders

||| Variant index for a provider
public export
providerIndex : ServiceProvider -> Nat
providerIndex p = fromMaybe 0 (map finToNat (findIndex (== p) providersSortedByHash))

-- =============================================================================
-- RPC Service (Chain + Provider)
-- =============================================================================

||| Complete RPC service specification
public export
record RpcService where
  constructor MkRpcService
  chain    : Chain
  provider : ServiceProvider

||| Default RPC service (EthMainnet + PublicNode)
public export
defaultRpcService : RpcService
defaultRpcService = MkRpcService EthMainnet PublicNode

-- =============================================================================
-- Debug/Display Helpers
-- =============================================================================

||| Show chain with its hash and index (for debugging)
public export
showChainDebug : Chain -> String
showChainDebug c =
  show c ++ " hash=" ++ hashToHex (chainHash c) ++ " idx=" ++ show (chainIndex c)

||| Show provider with its hash and index (for debugging)
public export
showProviderDebug : ServiceProvider -> String
showProviderDebug p =
  show p ++ " hash=" ++ hashToHex (providerHash p) ++ " idx=" ++ show (providerIndex p)
