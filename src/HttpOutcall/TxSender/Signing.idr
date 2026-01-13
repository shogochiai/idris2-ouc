||| Transaction Signing with Threshold ECDSA
|||
||| Integration of t-ECDSA for signing EVM transactions.
module HttpOutcall.TxSender.Signing

import FRMonad.Core
import HttpOutcall.TxSender.Types
import HttpOutcall.TxSender.Rlp
import ThresholdECDSA.Core
import ThresholdECDSA.FFI
import Data.List
import Data.Bits
import Control.Monad.Maybe

%default covering

-- =============================================================================
-- Transaction Signing
-- =============================================================================

||| Signing context
public export
record SigningContext where
  constructor MkSigningContext
  keyId          : KeyId
  derivationPath : DerivationPath

||| Create signing context for a chain
export
signingContextForChain : Nat -> Bool -> SigningContext
signingContextForChain chainId isProduction =
  MkSigningContext
    (if isProduction then productionKey else testKey)
    (evmDerivationPath chainId)

||| Parse DER-encoded signature
||| DER format: 0x30 len 0x02 rlen r 0x02 slen s
parseDerSignature : List Bits8 -> Maybe (List Bits8, List Bits8)
parseDerSignature der = do
  Prelude.guard $ length der >= 8
  Prelude.guard $ getAt 0 der == Just 0x30
  let totalLen = cast {to=Nat} (fromMaybe 0 $ getAt 1 der)
  Prelude.guard $ getAt 2 der == Just 0x02
  let rLen = cast {to=Nat} (fromMaybe 0 $ getAt 3 der)
  let r = take rLen $ drop 4 der
  Prelude.guard $ getAt (4 + rLen) der == Just 0x02
  let sLen = cast {to=Nat} (fromMaybe 0 $ getAt (5 + rLen) der)
  let s = take sLen $ drop (6 + rLen) der
  -- Normalize r and s to 32 bytes
  pure (normalize32 r, normalize32 s)
  where
    normalize32 : List Bits8 -> List Bits8
    normalize32 bytes =
      let stripped = dropWhile (== 0) bytes
      in replicate (32 `minus` length stripped) 0 ++ stripped

||| Sign transaction hash and return signature components (v, r, s)
||| Returns: (yParity, r, s) where yParity is 0 or 1
export
signTxHash : SigningContext -> List Bits8 -> IO (Either String (Bits8, List Bits8, List Bits8))
signTxHash ctx txHash = do
  -- Initiate signing
  success <- signWithEcdsa ctx.keyId ctx.derivationPath txHash
  if not success
    then pure (Left "Failed to initiate t-ECDSA signing")
    else do
      -- Get signature (async - in real impl would need to wait for callback)
      sigBytes <- getSignature
      if length sigBytes < 64
        then pure (Left "Signature not ready or too short")
        else do
          -- Parse DER signature to (r, s)
          case parseDerSignature sigBytes of
            Nothing => pure (Left "Failed to parse DER signature")
            Just (r, s) => do
              -- Recovery ID (v) - simplified, would need public key recovery
              let v = 0  -- Will be computed from chain ID
              pure (Right (v, r, s))

-- =============================================================================
-- Signed Transaction Construction
-- =============================================================================

||| Build signed EIP-1559 transaction
export
buildSignedTx : Eip1559Fields -> Bits8 -> List Bits8 -> List Bits8 -> String
buildSignedTx tx v r s =
  "0x" ++ rlpToHex (encodeEip1559Signed tx v r s)

||| Sign and encode transaction
export
signAndEncodeTx : SigningContext -> Eip1559Fields -> IO (Either String String)
signAndEncodeTx ctx tx = do
  let txForSigning = encodeEip1559ForSigning tx
  -- In real impl: hash with keccak256
  -- let txHash = keccak256 txForSigning
  let txHash = take 32 (txForSigning ++ replicate 32 0)  -- Placeholder
  result <- signTxHash ctx txHash
  case result of
    Left err => pure (Left err)
    Right (v, r, s) => pure (Right (buildSignedTx tx v r s))

-- =============================================================================
-- FR Integration
-- =============================================================================

||| Sign transaction with FR error handling
export
signTransactionFR : SigningContext -> Eip1559Fields -> FR String
signTransactionFR ctx tx =
  fail Update "signTransactionFR"
       "Transaction prepared for signing"
       (Internal "Async signing requires callback - use signAndEncodeTx in IO")

-- =============================================================================
-- Upgrade Transaction Building
-- =============================================================================

||| Build upgrade transaction fields
export
buildUpgradeTxFields :
  ChainTxConfig ->
  Nat ->           -- nonce
  String ->        -- to address
  String ->        -- calldata
  Eip1559Fields
buildUpgradeTxFields config nonce to calldata =
  MkEip1559Fields
    config.chainId
    nonce
    1000000000      -- 1 gwei priority fee
    config.maxGasPrice
    config.defaultGasLimit
    to
    0               -- no value
    calldata
    []              -- empty access list

||| Full upgrade signing flow
export
signUpgradeTx :
  ChainTxConfig ->
  Bool ->          -- isProduction
  Nat ->           -- nonce
  String ->        -- to address
  String ->        -- calldata
  IO (Either String String)
signUpgradeTx config isProduction nonce to calldata = do
  let ctx = signingContextForChain config.chainId isProduction
  let txFields = buildUpgradeTxFields config nonce to calldata
  signAndEncodeTx ctx txFields
