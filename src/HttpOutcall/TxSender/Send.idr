||| Transaction Sending Operations
|||
||| RPC-dependent operations for sending and tracking transactions.
module HttpOutcall.TxSender.Send

import FRMonad.Core
import HttpOutcall.TxSender.Types
import HttpOutcall.TxSender.Abi
import OUC.Functions.Signatures
import Util.StringHex
import Data.List

%default total

-- =============================================================================
-- Upgrade Execution Parameters
-- =============================================================================

||| Parameters for upgrade execution
public export
record UpgradeExecParams where
  constructor MkUpgradeExecParams
  chainConfig  : ChainTxConfig
  ouAddress    : String
  proxyAddress : String
  newImpl      : String
  signatures   : SignatureBundle
  nonce        : Nat
  maxGasPrice  : Nat

export
Show UpgradeExecParams where
  show p = "UpgradeExec{ou=" ++ p.ouAddress ++ ", proxy=" ++ p.proxyAddress ++ "}"

-- =============================================================================
-- Validation
-- =============================================================================

||| Validate upgrade parameters
public export
validateUpgradeParams : UpgradeExecParams -> FR ()
validateUpgradeParams params =
  if not (isHexPrefixed params.ouAddress) || length params.ouAddress /= 42
    then fail Update "validateUpgradeParams" "Invalid OU address"
              (DecodeError "OU address format invalid")
    else if not (isHexPrefixed params.proxyAddress) || length params.proxyAddress /= 42
      then fail Update "validateUpgradeParams" "Invalid proxy address"
                (DecodeError "Proxy address format invalid")
      else if not (isHexPrefixed params.newImpl) || length params.newImpl /= 42
        then fail Update "validateUpgradeParams" "Invalid implementation address"
                  (DecodeError "Implementation address format invalid")
        else if params.maxGasPrice > params.chainConfig.maxGasPrice
          then fail Update "validateUpgradeParams" "Gas price too high"
                    (InvalidState "Exceeds chain limit")
          else ok Update "validateUpgradeParams" "Valid" ()

-- =============================================================================
-- Transaction Operations
-- =============================================================================

||| Send upgrade transaction
public export
sendUpgradeTransaction : UpgradeExecParams -> FR TxHash
sendUpgradeTransaction params = do
  validateUpgradeParams params
  calldata <- buildUpgradeCalldata
        params.proxyAddress
        params.newImpl
        params.signatures.proposerSig
        (map snd params.signatures.auditorSigs)
  -- vetKey signing stub
  fail Update "sendUpgradeTransaction"
       ("Prepared tx to " ++ params.ouAddress)
       (Internal "vetKey signing not implemented")

||| Wait for confirmation
public export
waitForConfirmation : ChainTxConfig -> TxHash -> Nat -> FR TxReceipt
waitForConfirmation config txHash timeout =
  fail Update "waitForConfirmation"
       ("Waiting for " ++ show txHash)
       (Internal "Async polling not implemented")

||| Full upgrade execution
public export
executeUpgrade : UpgradeExecParams -> Nat -> FR TxReceipt
executeUpgrade params timeout = do
  txHash <- sendUpgradeTransaction params
  waitForConfirmation params.chainConfig txHash timeout

-- =============================================================================
-- Status Conversion
-- =============================================================================

||| Convert status to FR
public export
txStatusToFR : TxReceipt -> FR ()
txStatusToFR receipt = case receipt.status of
  TxConfirmed block =>
    ok Update "txStatusToFR" ("Confirmed at block " ++ show block) ()
  TxPending =>
    fail Update "txStatusToFR" "Still pending" (Timeout "Not confirmed")
  TxFailed reason =>
    fail Update "txStatusToFR" ("Failed: " ++ reason) (CallError reason)
