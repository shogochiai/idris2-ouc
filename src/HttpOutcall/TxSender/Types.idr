||| Transaction Types
|||
||| Pure data types for EVM transactions.
||| No FRC, no EvmRpc dependencies - just data.
module HttpOutcall.TxSender.Types

%default total

-- =============================================================================
-- Core Transaction Types
-- =============================================================================

||| Raw transaction bytes
public export
record RawTransaction where
  constructor MkRawTransaction
  hex : String

export
Show RawTransaction where
  show tx = "RawTx{len=" ++ show (length tx.hex) ++ "}"

||| Transaction hash (32 bytes)
public export
record TxHash where
  constructor MkTxHash
  hex : String

export
Show TxHash where
  show h = h.hex

export
Eq TxHash where
  h1 == h2 = h1.hex == h2.hex

||| Transaction status after submission
public export
data TxStatus
  = TxPending
  | TxConfirmed Nat
  | TxFailed String

export
Show TxStatus where
  show TxPending       = "Pending"
  show (TxConfirmed b) = "Confirmed at block " ++ show b
  show (TxFailed r)    = "Failed: " ++ r

||| Transaction receipt
public export
record TxReceipt where
  constructor MkTxReceipt
  txHash      : TxHash
  status      : TxStatus
  gasUsed     : Nat
  blockNumber : Maybe Nat
  logs        : List String

export
Show TxReceipt where
  show r = "TxReceipt{" ++ show r.txHash ++ ", " ++ show r.status ++ "}"

-- =============================================================================
-- Chain Configuration
-- =============================================================================

||| Chain-specific configuration
public export
record ChainTxConfig where
  constructor MkChainTxConfig
  chainId         : Nat
  rpcUrl          : String
  maxGasPrice     : Nat
  defaultGasLimit : Nat
  confirmations   : Nat
  blockTime       : Nat

export
Show ChainTxConfig where
  show c = "Chain(" ++ show c.chainId ++ ")"

||| Ethereum Mainnet
public export
ethereumMainnet : ChainTxConfig
ethereumMainnet = MkChainTxConfig 1 "https://eth.llamarpc.com" 100000000000 500000 12 12

||| Base Mainnet
public export
baseMainnet : ChainTxConfig
baseMainnet = MkChainTxConfig 8453 "https://mainnet.base.org" 1000000000 500000 12 2

||| Arbitrum One
public export
arbitrumOne : ChainTxConfig
arbitrumOne = MkChainTxConfig 42161 "https://arb1.arbitrum.io/rpc" 1000000000 2000000 12 1

||| Get chain config by ID
public export
getChainConfig : Nat -> Maybe ChainTxConfig
getChainConfig 1     = Just ethereumMainnet
getChainConfig 8453  = Just baseMainnet
getChainConfig 42161 = Just arbitrumOne
getChainConfig _     = Nothing

-- =============================================================================
-- Transaction Parameters
-- =============================================================================

||| EIP-1559 transaction parameters
public export
record TxParams where
  constructor MkTxParams
  chainId        : Nat
  nonce          : Nat
  maxFeePerGas   : Nat
  maxPriorityFee : Nat
  gasLimit       : Nat
  to             : String
  value          : Nat
  data_          : String

export
Show TxParams where
  show p = "TxParams{to=" ++ p.to ++ ", gas=" ++ show p.gasLimit ++ "}"

||| Legacy transaction parameters
public export
record LegacyTxParams where
  constructor MkLegacyTxParams
  chainId  : Nat
  nonce    : Nat
  gasPrice : Nat
  gasLimit : Nat
  to       : String
  value    : Nat
  data_    : String

-- =============================================================================
-- Status Helpers (pure functions, no FR)
-- =============================================================================

||| Check if confirmed
public export
isTxConfirmed : TxReceipt -> Bool
isTxConfirmed receipt = case receipt.status of
  TxConfirmed _ => True
  _             => False

||| Check if failed
public export
isTxFailed : TxReceipt -> Bool
isTxFailed receipt = case receipt.status of
  TxFailed _ => True
  _          => False

||| Get failure reason
public export
getTxFailureReason : TxReceipt -> Maybe String
getTxFailureReason receipt = case receipt.status of
  TxFailed reason => Just reason
  _               => Nothing
