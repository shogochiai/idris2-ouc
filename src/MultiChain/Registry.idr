||| Multi-Chain Registry
|||
||| Chain configuration and registry management for cross-chain upgrades.
||| Supports Ethereum, Arbitrum, Base, and other EVM-compatible chains.
module MultiChain.Registry

import Data.List

%default total

-- =============================================================================
-- Chain ID
-- =============================================================================

||| Chain identifier (EIP-155)
public export
record ChainId where
  constructor MkChainId
  value : Nat

public export
Show ChainId where
  show c = show c.value

public export
Eq ChainId where
  c1 == c2 = c1.value == c2.value

public export
Ord ChainId where
  compare c1 c2 = compare c1.value c2.value

||| Well-known chain IDs
export
ethereumMainnet : ChainId
ethereumMainnet = MkChainId 1

export
arbitrumOne : ChainId
arbitrumOne = MkChainId 42161

export
baseMainnet : ChainId
baseMainnet = MkChainId 8453

export
optimism : ChainId
optimism = MkChainId 10

export
polygon : ChainId
polygon = MkChainId 137

export
avalanche : ChainId
avalanche = MkChainId 43114

-- =============================================================================
-- EVM Address
-- =============================================================================

||| EVM address (20 bytes as hex string)
public export
record EvmAddress where
  constructor MkEvmAddress
  hex : String

public export
Show EvmAddress where
  show addr = addr.hex

public export
Eq EvmAddress where
  a1 == a2 = a1.hex == a2.hex

||| Zero address
export
zeroAddress : EvmAddress
zeroAddress = MkEvmAddress "0x0000000000000000000000000000000000000000"

-- =============================================================================
-- Chain Configuration
-- =============================================================================

||| Chain configuration
public export
record ChainConfig where
  constructor MkChainConfig
  chainId         : ChainId
  name            : String
  rpcUrl          : String           -- Primary RPC endpoint
  rpcBackups      : List String      -- Fallback endpoints
  oufAddr         : EvmAddress       -- OptimisticUpgraderFactory
  dictionaryAddr  : EvmAddress       -- Shared Dictionary
  blockTime       : Nat              -- Average block time (ms)
  confirmations   : Nat              -- Required confirmations
  gasMultiplier   : Nat              -- Gas estimate multiplier (basis points)
  isActive        : Bool
  addedAt         : Nat

public export
Show ChainConfig where
  show c = c.name ++ " (" ++ show c.chainId ++ ")"

-- =============================================================================
-- Chain Status
-- =============================================================================

||| Chain operational status
public export
data ChainStatus
  = Healthy
  | Degraded String          -- Warning message
  | Unhealthy String         -- Error message
  | Offline

public export
Show ChainStatus where
  show Healthy = "Healthy"
  show (Degraded msg) = "Degraded: " ++ msg
  show (Unhealthy msg) = "Unhealthy: " ++ msg
  show Offline = "Offline"

public export
Eq ChainStatus where
  Healthy == Healthy = True
  (Degraded _) == (Degraded _) = True
  (Unhealthy _) == (Unhealthy _) = True
  Offline == Offline = True
  _ == _ = False

-- =============================================================================
-- Chain Registry
-- =============================================================================

||| Chain registry state
public export
record ChainRegistry where
  constructor MkChainRegistry
  chains          : List ChainConfig
  defaultChain    : ChainId
  lastUpdated     : Nat

public export
emptyRegistry : ChainRegistry
emptyRegistry = MkChainRegistry [] ethereumMainnet 0

-- =============================================================================
-- Registry Operations
-- =============================================================================

||| Add chain to registry
public export
addChain : ChainRegistry -> ChainConfig -> Nat -> Either String ChainRegistry
addChain registry config now =
  case find (\c => c.chainId == config.chainId) registry.chains of
    Just _ => Left ("Chain " ++ show config.chainId ++ " already registered")
    Nothing =>
      let updated = { chains := config :: registry.chains, lastUpdated := now } registry
      in Right updated

||| Get chain configuration by ID
public export
getChain : ChainRegistry -> ChainId -> Maybe ChainConfig
getChain registry chainId = find (\c => c.chainId == chainId) registry.chains

||| Update chain configuration
public export
updateChain : ChainRegistry -> ChainConfig -> Nat -> Either String ChainRegistry
updateChain registry config now =
  case find (\c => c.chainId == config.chainId) registry.chains of
    Nothing => Left ("Chain " ++ show config.chainId ++ " not found")
    Just _ =>
      let updated = map (\c => if c.chainId == config.chainId then config else c) registry.chains
      in Right ({ chains := updated, lastUpdated := now } registry)

||| Remove chain from registry
public export
removeChain : ChainRegistry -> ChainId -> Nat -> Either String ChainRegistry
removeChain registry chainId now =
  case find (\c => c.chainId == chainId) registry.chains of
    Nothing => Left ("Chain " ++ show chainId ++ " not found")
    Just _ =>
      let updated = filter (\c => not (c.chainId == chainId)) registry.chains
      in Right ({ chains := updated, lastUpdated := now } registry)

||| Get all active chains
public export
getActiveChains : ChainRegistry -> List ChainConfig
getActiveChains registry = filter (.isActive) registry.chains

||| Get chain count
public export
getChainCount : ChainRegistry -> Nat
getChainCount registry = length registry.chains

||| Set default chain
public export
setDefaultChain : ChainRegistry -> ChainId -> Nat -> Either String ChainRegistry
setDefaultChain registry chainId now =
  case find (\c => c.chainId == chainId) registry.chains of
    Nothing => Left ("Chain " ++ show chainId ++ " not found")
    Just _ => Right ({ defaultChain := chainId, lastUpdated := now } registry)

||| Activate chain
public export
activateChain : ChainRegistry -> ChainId -> Nat -> Either String ChainRegistry
activateChain registry chainId now =
  let activate : ChainConfig -> ChainConfig
      activate c = if c.chainId == chainId then { isActive := True } c else c
      updated = map activate registry.chains
  in Right ({ chains := updated, lastUpdated := now } registry)

||| Deactivate chain
public export
deactivateChain : ChainRegistry -> ChainId -> Nat -> Either String ChainRegistry
deactivateChain registry chainId now =
  let deactivate : ChainConfig -> ChainConfig
      deactivate c = if c.chainId == chainId then { isActive := False } c else c
      updated = map deactivate registry.chains
  in Right ({ chains := updated, lastUpdated := now } registry)

-- =============================================================================
-- Default Chain Configurations
-- =============================================================================

||| Ethereum Mainnet default config
export
defaultEthereumConfig : ChainConfig
defaultEthereumConfig = MkChainConfig
  ethereumMainnet
  "Ethereum"
  "https://eth.llamarpc.com"
  ["https://rpc.ankr.com/eth", "https://eth.drpc.org"]
  zeroAddress
  zeroAddress
  12000       -- 12 second block time
  12          -- 12 confirmations
  12000       -- 120% gas multiplier
  True
  0

||| Arbitrum One default config
export
defaultArbitrumConfig : ChainConfig
defaultArbitrumConfig = MkChainConfig
  arbitrumOne
  "Arbitrum"
  "https://arb1.arbitrum.io/rpc"
  ["https://rpc.ankr.com/arbitrum", "https://arbitrum.drpc.org"]
  zeroAddress
  zeroAddress
  250         -- 250ms block time
  1           -- 1 confirmation (L2)
  11000       -- 110% gas multiplier
  True
  0

||| Base Mainnet default config
export
defaultBaseConfig : ChainConfig
defaultBaseConfig = MkChainConfig
  baseMainnet
  "Base"
  "https://mainnet.base.org"
  ["https://base.drpc.org", "https://rpc.ankr.com/base"]
  zeroAddress
  zeroAddress
  2000        -- 2 second block time
  1           -- 1 confirmation (L2)
  11000       -- 110% gas multiplier
  True
  0

||| Initialize registry with default chains
export
initDefaultRegistry : Nat -> ChainRegistry
initDefaultRegistry now = MkChainRegistry
  [defaultEthereumConfig, defaultArbitrumConfig, defaultBaseConfig]
  ethereumMainnet
  now
