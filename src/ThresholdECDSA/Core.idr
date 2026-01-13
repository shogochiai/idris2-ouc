||| Threshold ECDSA Core Types
|||
||| Types for ICP chain-key signatures used for EVM transaction signing.
module ThresholdECDSA.Core

import Data.List
import Data.Bits

%default total

-- =============================================================================
-- ECDSA Curve
-- =============================================================================

||| ECDSA curve type (currently only secp256k1 supported)
public export
data EcdsaCurve = Secp256k1

public export
Show EcdsaCurve where
  show Secp256k1 = "secp256k1"

public export
Eq EcdsaCurve where
  Secp256k1 == Secp256k1 = True

-- =============================================================================
-- Key Identifier
-- =============================================================================

||| Key identifier for t-ECDSA operations
public export
record KeyId where
  constructor MkKeyId
  curve : EcdsaCurve
  name  : String

public export
Show KeyId where
  show k = "KeyId(" ++ show k.curve ++ ", \"" ++ k.name ++ "\")"

public export
Eq KeyId where
  k1 == k2 = k1.curve == k2.curve && k1.name == k2.name

||| Production key (34-node fiduciary subnet)
||| Cost: 25B cycles per signature
export
productionKey : KeyId
productionKey = MkKeyId Secp256k1 "key_1"

||| Test key (13-node subnet, mainnet)
||| Cost: 10B cycles per signature
export
testKey : KeyId
testKey = MkKeyId Secp256k1 "test_key_1"

||| Local development key (dfx local replica)
||| Cost: 0 cycles
export
localKey : KeyId
localKey = MkKeyId Secp256k1 "dfx_test_key"

||| Key type enumeration for FFI
public export
data KeyType = Production | Test | Local

public export
Eq KeyType where
  Production == Production = True
  Test == Test = True
  Local == Local = True
  _ == _ = False

public export
keyTypeToInt : KeyType -> Int
keyTypeToInt Production = 0
keyTypeToInt Test = 1
keyTypeToInt Local = 2

public export
keyIdToType : KeyId -> KeyType
keyIdToType k =
  if k.name == "key_1" then Production
  else if k.name == "test_key_1" then Test
  else Local

-- =============================================================================
-- Derivation Path
-- =============================================================================

||| Derivation path for key derivation (BIP-32 style)
||| Each segment is 4 bytes (big-endian)
public export
record DerivationPath where
  constructor MkDerivationPath
  segments : List Bits32

public export
Show DerivationPath where
  show p = "m/" ++ showPath p.segments
    where
      showPath : List Bits32 -> String
      showPath [] = ""
      showPath [x] = show (cast {to=Nat} x)
      showPath (x :: xs) = show (cast {to=Nat} x) ++ "/" ++ showPath xs

||| Empty derivation path
export
emptyPath : DerivationPath
emptyPath = MkDerivationPath []

||| BIP-44 constants
export
bip44Purpose : Bits32
bip44Purpose = 0x8000002C  -- 44' (hardened)

export
bip44CoinEth : Bits32
bip44CoinEth = 0x8000003C  -- 60' (ETH coin type, hardened)

||| Build EVM derivation path for chain ID
||| Path: m/44'/60'/0'/0/{chainId}
export
evmDerivationPath : Nat -> DerivationPath
evmDerivationPath chainId =
  MkDerivationPath
    [ bip44Purpose         -- 44' (purpose)
    , bip44CoinEth         -- 60' (ETH)
    , 0x80000000           -- 0'  (account, hardened)
    , 0x00000000           -- 0   (change)
    , cast chainId         -- chain ID (index)
    ]

-- =============================================================================
-- Signature
-- =============================================================================

||| ECDSA signature (r, s components)
public export
record EcdsaSignature where
  constructor MkEcdsaSignature
  r : List Bits8   -- 32 bytes
  s : List Bits8   -- 32 bytes

||| DER-encoded signature
public export
record DerSignature where
  constructor MkDerSignature
  bytes : List Bits8

||| Signing status
public export
data SignStatus
  = Pending
  | Success
  | Error String

public export
Show SignStatus where
  show Pending = "Pending"
  show Success = "Success"
  show (Error msg) = "Error: " ++ msg

-- =============================================================================
-- Public Key
-- =============================================================================

||| SEC1 public key (compressed or uncompressed)
public export
record PublicKey where
  constructor MkPublicKey
  bytes : List Bits8

||| Chain code for BIP-32 derivation
public export
record ChainCode where
  constructor MkChainCode
  bytes : List Bits8  -- 32 bytes

||| Public key result from ecdsa_public_key
public export
record PublicKeyResult where
  constructor MkPublicKeyResult
  publicKey : PublicKey
  chainCode : ChainCode

-- =============================================================================
-- EVM Address
-- =============================================================================

||| EVM address (20 bytes)
public export
record EvmAddress where
  constructor MkEvmAddress
  bytes : List Bits8  -- 20 bytes

hexDigitEvm : Nat -> String
hexDigitEvm n =
  if n < 10 then cast (cast {to=Int} n + 48)
  else cast (cast {to=Int} n + 87)

showHexByte : Bits8 -> String
showHexByte b =
  let hi = cast {to=Nat} (b `shiftR` 4)
      lo = cast {to=Nat} (b .&. 0x0F)
  in hexDigitEvm hi ++ hexDigitEvm lo

public export
Show EvmAddress where
  show addr = "0x" ++ concatMap showHexByte addr.bytes

-- =============================================================================
-- Cycle Costs
-- =============================================================================

||| Cycle cost for signing operation
public export
signCycles : KeyType -> Nat
signCycles Production = 25000000000  -- 25B cycles
signCycles Test = 10000000000        -- 10B cycles
signCycles Local = 0                 -- Free on local

||| Cycle cost for public key retrieval (always free)
public export
pubkeyCycles : Nat
pubkeyCycles = 0
