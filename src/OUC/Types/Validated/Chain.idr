||| Known EVM Chain Types
module OUC.Types.Validated.Chain

import Data.Nat

%default total

-- =============================================================================
-- KnownChain: Type-safe EVM chain identifiers
-- =============================================================================

||| Known EVM chain identifiers
public export
data KnownChain
  = EthMainnet      -- Chain ID: 1
  | EthSepolia      -- Chain ID: 11155111
  | ArbitrumOne     -- Chain ID: 42161
  | ArbitrumSepolia -- Chain ID: 421614
  | BaseMainnet     -- Chain ID: 8453
  | BaseSepolia     -- Chain ID: 84532
  | CustomChain Nat -- For testing/private chains

||| Get numeric chain ID
public export
chainIdValue : KnownChain -> Nat
chainIdValue EthMainnet      = 1
chainIdValue EthSepolia      = 11155111
chainIdValue ArbitrumOne     = 42161
chainIdValue ArbitrumSepolia = 421614
chainIdValue BaseMainnet     = 8453
chainIdValue BaseSepolia     = 84532
chainIdValue (CustomChain n) = n

||| Parse numeric chain ID to known chain
public export
mkKnownChain : Nat -> KnownChain
mkKnownChain n =
  if n == 1        then EthMainnet
  else if n == 11155111 then EthSepolia
  else if n == 42161    then ArbitrumOne
  else if n == 421614   then ArbitrumSepolia
  else if n == 8453     then BaseMainnet
  else if n == 84532    then BaseSepolia
  else CustomChain n

||| Check if chain is a mainnet
public export
isMainnet : KnownChain -> Bool
isMainnet EthMainnet   = True
isMainnet ArbitrumOne  = True
isMainnet BaseMainnet  = True
isMainnet _            = False

||| Check if chain is a testnet
public export
isTestnet : KnownChain -> Bool
isTestnet EthSepolia      = True
isTestnet ArbitrumSepolia = True
isTestnet BaseSepolia     = True
isTestnet _               = False

public export
Show KnownChain where
  show EthMainnet      = "Ethereum"
  show EthSepolia      = "Sepolia"
  show ArbitrumOne     = "Arbitrum"
  show ArbitrumSepolia = "ArbitrumSepolia"
  show BaseMainnet     = "Base"
  show BaseSepolia     = "BaseSepolia"
  show (CustomChain n) = "Custom(" ++ show n ++ ")"

public export
Eq KnownChain where
  c1 == c2 = chainIdValue c1 == chainIdValue c2
