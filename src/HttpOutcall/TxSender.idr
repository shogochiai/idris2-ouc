||| Transaction Sender Module
|||
||| Handles signed transaction construction and submission to EVM chains.
||| Integrates with OUC's aggregated signatures for upgrade execution.
module HttpOutcall.TxSender

import FRC.Core
import HttpOutcall.Core
import HttpOutcall.EvmRpc
import OUC.Core
import OUC.MultiSig
import Data.List
import Data.String
import Util.StringHex

%default total

-- =============================================================================
-- Transaction Types
-- =============================================================================

||| Raw transaction bytes
public export
record RawTransaction where
  constructor MkRawTransaction
  hex : String                    -- 0x-prefixed RLP-encoded transaction

public export
Show RawTransaction where
  show tx = "RawTx{len=" ++ show (length tx.hex) ++ "}"

||| Transaction hash (32 bytes)
public export
record TxHash where
  constructor MkTxHash
  hex : String                    -- 0x-prefixed 32-byte hash

public export
Show TxHash where
  show h = h.hex

public export
Eq TxHash where
  h1 == h2 = h1.hex == h2.hex

||| Transaction status after submission
public export
data TxStatus
  = TxPending
  | TxConfirmed Nat               -- Block number
  | TxFailed String               -- Failure reason

public export
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
  logs        : List String       -- Encoded log entries

public export
Show TxReceipt where
  show r = "TxReceipt{" ++ show r.txHash ++ ", " ++ show r.status ++ "}"

-- =============================================================================
-- Chain Configuration
-- =============================================================================

||| Chain-specific configuration for transaction sending
public export
record ChainTxConfig where
  constructor MkChainTxConfig
  chainId       : Nat
  rpcUrl        : String
  maxGasPrice   : Nat              -- Max gas price in wei
  defaultGasLimit : Nat            -- Default gas limit
  confirmations : Nat              -- Required confirmations
  blockTime     : Nat              -- Average block time in seconds

public export
Show ChainTxConfig where
  show c = "Chain(" ++ show c.chainId ++ ")"

||| Ethereum Mainnet config
public export
ethereumMainnet : ChainTxConfig
ethereumMainnet = MkChainTxConfig 1 "https://eth.llamarpc.com" 100000000000 500000 12 12

||| Base Mainnet config
public export
baseMainnet : ChainTxConfig
baseMainnet = MkChainTxConfig 8453 "https://mainnet.base.org" 1000000000 500000 12 2

||| Arbitrum One config
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
  chainId       : Nat
  nonce         : Nat
  maxFeePerGas  : Nat              -- Max total fee per gas
  maxPriorityFee: Nat              -- Max priority fee (tip)
  gasLimit      : Nat
  to            : String           -- Destination address
  value         : Nat              -- Wei to send
  data_         : String           -- Calldata (0x-prefixed)

public export
Show TxParams where
  show p = "TxParams{to=" ++ p.to ++ ", gas=" ++ show p.gasLimit ++ "}"

||| Legacy transaction parameters (for chains not supporting EIP-1559)
public export
record LegacyTxParams where
  constructor MkLegacyTxParams
  chainId   : Nat
  nonce     : Nat
  gasPrice  : Nat
  gasLimit  : Nat
  to        : String
  value     : Nat
  data_     : String

-- =============================================================================
-- Upgrade Execution Parameters
-- =============================================================================

||| Parameters for executing upgrade via OU contract
public export
record UpgradeExecParams where
  constructor MkUpgradeExecParams
  chainConfig  : ChainTxConfig
  ouAddress    : String           -- OptimisticUpgrader contract
  proxyAddress : String           -- ERC-7546 proxy to upgrade
  newImpl      : String           -- New implementation address
  signatures   : AggregatedSignatures
  nonce        : Nat
  maxGasPrice  : Nat

public export
Show UpgradeExecParams where
  show p = "UpgradeExec{ou=" ++ p.ouAddress ++ ", proxy=" ++ p.proxyAddress ++ "}"

-- =============================================================================
-- Calldata Construction
-- =============================================================================

-- =============================================================================
-- OU Contract Function Selectors
-- =============================================================================

||| castVote(uint256 proposalId, uint8 decision, bytes32 sigHash)
public export
SEL_CAST_VOTE : String
SEL_CAST_VOTE = "0x5c19a95c"

||| submitProposerSignature(uint256 proposalId, bytes32 sigHash)
public export
SEL_SUBMIT_PROPOSER_SIG : String
SEL_SUBMIT_PROPOSER_SIG = "0x7d4b1d9e"

||| getVotingStatus(uint256 proposalId) -> (uint256, uint256, bool)
public export
SEL_GET_VOTING_STATUS : String
SEL_GET_VOTING_STATUS = "0x8a2c7b5e"

||| createProposal(uint256, address, address, bytes4, uint256)
public export
SEL_CREATE_PROPOSAL : String
SEL_CREATE_PROPOSAL = "0x3b2d5c8a"

||| Legacy: executeUpgrade (deprecated - OU now auto-executes on threshold)
public export
EXECUTE_UPGRADE_SELECTOR : String
EXECUTE_UPGRADE_SELECTOR = "0x7b0472f0"

||| Encode address as ABI parameter
encodeAddress : String -> String
encodeAddress addr = padTo32 addr

||| Build upgrade calldata for OU contract
public export
buildUpgradeCalldata :
  String ->           -- proxy address
  String ->           -- new implementation
  String ->           -- proposer signature
  List String ->      -- auditor signatures
  FR String
buildUpgradeCalldata proxy newImpl proposerSig auditorSigs =
  if not (isHexPrefixed proxy) || length proxy /= 42
    then fail Update "buildUpgradeCalldata" "Invalid proxy address"
              (DecodeError "Proxy address format invalid")
    else if not (isHexPrefixed newImpl) || length newImpl /= 42
      then fail Update "buildUpgradeCalldata" "Invalid implementation address"
                (DecodeError "Implementation address format invalid")
      else
        -- Simplified ABI encoding
        -- Real implementation would properly encode dynamic types
        let proxyEnc = encodeAddress proxy
            implEnc = encodeAddress newImpl
            -- For now, return selector + encoded addresses
            calldata = EXECUTE_UPGRADE_SELECTOR ++ proxyEnc ++ implEnc
        in ok Update "buildUpgradeCalldata"
              ("Built calldata: " ++ show (length calldata) ++ " chars")
              calldata

-- =============================================================================
-- Transaction Sending (FRC-compliant)
-- =============================================================================

||| Validate upgrade execution parameters
public export
validateUpgradeParams :
  UpgradeExecParams ->
  FR ()
validateUpgradeParams params = do
  -- Validate addresses
  if not (isHexPrefixed params.ouAddress) || length params.ouAddress /= 42
    then fail Update "validateUpgradeParams" "Invalid OU address"
              (DecodeError "OU address format invalid")
    else if not (isHexPrefixed params.proxyAddress) || length params.proxyAddress /= 42
      then fail Update "validateUpgradeParams" "Invalid proxy address"
                (DecodeError "Proxy address format invalid")
      else if not (isHexPrefixed params.newImpl) || length params.newImpl /= 42
        then fail Update "validateUpgradeParams" "Invalid implementation address"
                  (DecodeError "Implementation address format invalid")
        else
          -- Validate gas price
          if params.maxGasPrice > params.chainConfig.maxGasPrice
            then fail Update "validateUpgradeParams" "Gas price too high"
                      (InvalidState ("Max gas price " ++ show params.maxGasPrice ++
                                    " exceeds chain limit " ++ show params.chainConfig.maxGasPrice))
            else ok Update "validateUpgradeParams" "Parameters valid" ()

||| Send upgrade transaction via OU contract
public export
sendUpgradeTransaction :
  UpgradeExecParams ->
  FR TxHash
sendUpgradeTransaction params = do
  -- Step 1: Validate parameters
  validateUpgradeParams params

  -- Step 2: Build calldata
  calldata <- buildUpgradeCalldata
        params.proxyAddress
        params.newImpl
        params.signatures.proposerSig
        (map snd params.signatures.auditorSigs)

  -- Step 3: Build transaction parameters
  let txParams = MkTxParams
        params.chainConfig.chainId
        params.nonce
        params.maxGasPrice
        (params.maxGasPrice `div` 10)  -- Priority fee = 10% of max
        params.chainConfig.defaultGasLimit
        params.ouAddress
        0  -- No ETH value
        calldata

  -- Step 4: Sign transaction with vetKey
  -- This requires integration with ICP's threshold ECDSA (vetKeys)
  fail Update "sendUpgradeTransaction"
       ("Prepared tx to " ++ params.ouAddress)
       (Internal "vetKey signing not yet implemented")

||| Wait for transaction confirmation
public export
waitForConfirmation :
  ChainTxConfig ->
  TxHash ->
  Nat ->              -- timeout in seconds
  FR TxReceipt
waitForConfirmation config txHash timeout = do
  -- Would implement polling loop:
  -- 1. Call getTransactionReceipt
  -- 2. If null, wait and retry
  -- 3. If found, check block confirmations
  -- 4. Return receipt or timeout
  fail Update "waitForConfirmation"
       ("Waiting for " ++ show txHash)
       (Internal "Async polling not yet implemented")

||| Full upgrade execution flow
public export
executeUpgrade :
  UpgradeExecParams ->
  Nat ->              -- confirmation timeout
  FR TxReceipt
executeUpgrade params timeout = do
  -- Send transaction
  txHash <- sendUpgradeTransaction params

  -- Wait for confirmation
  waitForConfirmation params.chainConfig txHash timeout

-- =============================================================================
-- Transaction Status Checking
-- =============================================================================

||| Check if transaction is confirmed
public export
isTxConfirmed : TxReceipt -> Bool
isTxConfirmed receipt = case receipt.status of
  TxConfirmed _ => True
  _ => False

||| Check if transaction failed
public export
isTxFailed : TxReceipt -> Bool
isTxFailed receipt = case receipt.status of
  TxFailed _ => True
  _ => False

||| Get failure reason if failed
public export
getTxFailureReason : TxReceipt -> Maybe String
getTxFailureReason receipt = case receipt.status of
  TxFailed reason => Just reason
  _ => Nothing

||| Convert transaction status to FR result
public export
txStatusToFR : TxReceipt -> FR ()
txStatusToFR receipt = case receipt.status of
  TxConfirmed block =>
    ok Update "txStatusToFR" ("Confirmed at block " ++ show block) ()
  TxPending =>
    fail Update "txStatusToFR" "Transaction still pending"
         (Timeout "Transaction not yet confirmed")
  TxFailed reason =>
    fail Update "txStatusToFR" ("Transaction failed: " ++ reason)
         (CallError reason)
