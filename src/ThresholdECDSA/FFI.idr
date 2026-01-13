||| Threshold ECDSA FFI Bindings
|||
||| C FFI for ICP t-ECDSA operations.
module ThresholdECDSA.FFI

import ThresholdECDSA.Core
import Data.List
import Data.Bits

%default covering

-- =============================================================================
-- FFI Declarations
-- =============================================================================

||| Set message hash for signing (32 bytes as 8 x uint32)
export
%foreign "C:ouc_ecdsa_set_message_hash,libic0"
prim__setMessageHash :
  Bits32 -> Bits32 -> Bits32 -> Bits32 ->
  Bits32 -> Bits32 -> Bits32 -> Bits32 ->
  PrimIO ()

||| Set key type: 0=production, 1=test, 2=local
export
%foreign "C:ouc_ecdsa_set_key,libic0"
prim__setKey : Int -> PrimIO ()

||| Set derivation path segment
export
%foreign "C:ouc_ecdsa_set_derivation_segment,libic0"
prim__setDerivationSegment : Int -> Bits32 -> PrimIO ()

||| Clear derivation path
export
%foreign "C:ouc_ecdsa_clear_path,libic0"
prim__clearPath : PrimIO ()

||| Initiate sign_with_ecdsa call
||| Returns 0 on success, error code otherwise
export
%foreign "C:ouc_ecdsa_sign,libic0"
prim__sign : PrimIO Int

||| Get signing status: 0=pending, 1=success, -1=error
export
%foreign "C:ouc_ecdsa_get_status,libic0"
prim__getStatus : PrimIO Int

||| Get signature length
export
%foreign "C:ouc_ecdsa_get_signature_len,libic0"
prim__getSignatureLen : PrimIO Int

||| Get signature byte at index
export
%foreign "C:ouc_ecdsa_get_signature_byte,libic0"
prim__getSignatureByte : Int -> PrimIO Int

||| Get public key length
export
%foreign "C:ouc_ecdsa_get_pubkey_len,libic0"
prim__getPubkeyLen : PrimIO Int

||| Get public key byte at index
export
%foreign "C:ouc_ecdsa_get_pubkey_byte,libic0"
prim__getPubkeyByte : Int -> PrimIO Int

-- =============================================================================
-- High-level API
-- =============================================================================

||| Set the message hash to sign
export
setMessageHash : List Bits8 -> IO ()
setMessageHash hash = do
  let padded = take 32 (hash ++ replicate 32 0)
  let h0 = bytesToWord (take 4 padded)
  let h1 = bytesToWord (take 4 (drop 4 padded))
  let h2 = bytesToWord (take 4 (drop 8 padded))
  let h3 = bytesToWord (take 4 (drop 12 padded))
  let h4 = bytesToWord (take 4 (drop 16 padded))
  let h5 = bytesToWord (take 4 (drop 20 padded))
  let h6 = bytesToWord (take 4 (drop 24 padded))
  let h7 = bytesToWord (take 4 (drop 28 padded))
  primIO $ prim__setMessageHash h0 h1 h2 h3 h4 h5 h6 h7
  where
    bytesToWord : List Bits8 -> Bits32
    bytesToWord bs =
      let b0 = cast {to=Bits32} (fromMaybe 0 (head' bs))
          b1 = cast {to=Bits32} (fromMaybe 0 (head' (drop 1 bs)))
          b2 = cast {to=Bits32} (fromMaybe 0 (head' (drop 2 bs)))
          b3 = cast {to=Bits32} (fromMaybe 0 (head' (drop 3 bs)))
      in (b0 `shiftL` 24) .|. (b1 `shiftL` 16) .|. (b2 `shiftL` 8) .|. b3

||| Set the key to use for signing
export
setKey : KeyId -> IO ()
setKey keyId = primIO $ prim__setKey (keyTypeToInt (keyIdToType keyId))

||| Set derivation path
export
setDerivationPath : DerivationPath -> IO ()
setDerivationPath path = do
  primIO prim__clearPath
  setSegments 0 path.segments
  where
    setSegments : Int -> List Bits32 -> IO ()
    setSegments _ [] = pure ()
    setSegments i (s :: ss) = do
      primIO $ prim__setDerivationSegment i s
      setSegments (i + 1) ss

||| Initiate signing operation
||| Returns True if call was initiated successfully
export
initiateSign : IO Bool
initiateSign = do
  result <- primIO prim__sign
  pure (result == 0)

||| Get current signing status
export
getSignStatus : IO SignStatus
getSignStatus = do
  status <- primIO prim__getStatus
  pure $ case status of
    0 => Pending
    1 => Success
    _ => Error "Signing failed"

||| Get signature bytes (DER encoded)
export
getSignature : IO (List Bits8)
getSignature = do
  len <- primIO prim__getSignatureLen
  if len <= 0
    then pure []
    else getBytes 0 len
  where
    getBytes : Int -> Int -> IO (List Bits8)
    getBytes i n =
      if i >= n
        then pure []
        else do
          b <- primIO $ prim__getSignatureByte i
          rest <- getBytes (i + 1) n
          pure (cast b :: rest)

||| Get public key bytes (SEC1 encoded)
export
getPublicKey : IO (List Bits8)
getPublicKey = do
  len <- primIO prim__getPubkeyLen
  if len <= 0
    then pure []
    else getBytes 0 len
  where
    getBytes : Int -> Int -> IO (List Bits8)
    getBytes i n =
      if i >= n
        then pure []
        else do
          b <- primIO $ prim__getPubkeyByte i
          rest <- getBytes (i + 1) n
          pure (cast b :: rest)

-- =============================================================================
-- Combined Operations
-- =============================================================================

||| Sign a message hash with the specified key and derivation path
||| Returns True if the async call was initiated successfully
export
signWithEcdsa : KeyId -> DerivationPath -> List Bits8 -> IO Bool
signWithEcdsa keyId path messageHash = do
  setKey keyId
  setDerivationPath path
  setMessageHash messageHash
  initiateSign
