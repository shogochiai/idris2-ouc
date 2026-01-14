||| ICRC-1 Ledger Candid Interface
|||
||| Provides Candid encoding for ICRC-1 standard methods.
||| Used to interact with ckETH and other ICRC-1 tokens.
|||
||| Reference: https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-1/README.md
module Candid.Icrc1

import Candid.Encoder
import Candid.Leb128
import Candid.Hash
import Data.Bits
import Data.List
import Data.String

%default total

-- =============================================================================
-- ckETH Ledger Canister IDs
-- =============================================================================

||| ckETH Ledger Canister ID (mainnet)
||| ss2fx-dyaaa-aaaar-qacoq-cai
public export
CKETH_LEDGER_MAINNET : String
CKETH_LEDGER_MAINNET = "ss2fx-dyaaa-aaaar-qacoq-cai"

||| ckETH Minter Canister ID (mainnet)
||| sv3dd-oaaaa-aaaar-qacoa-cai
public export
CKETH_MINTER_MAINNET : String
CKETH_MINTER_MAINNET = "sv3dd-oaaaa-aaaar-qacoa-cai"

-- =============================================================================
-- ICRC-1 Account Type
-- =============================================================================

||| ICRC-1 Account: owner principal + optional subaccount
public export
record Icrc1Account where
  constructor MkIcrc1Account
  ||| Owner principal (as raw bytes)
  owner      : List Bits8
  ||| Optional subaccount (32 bytes, Nothing for default)
  subaccount : Maybe (List Bits8)

||| Create account with default subaccount
public export
defaultAccount : List Bits8 -> Icrc1Account
defaultAccount principal = MkIcrc1Account principal Nothing

||| Create account with specific subaccount
public export
accountWithSubaccount : List Bits8 -> List Bits8 -> Icrc1Account
accountWithSubaccount principal sub = MkIcrc1Account principal (Just sub)

-- =============================================================================
-- Candid Type Indices (ICRC-1 specific)
-- =============================================================================

-- Candid primitive type indices (negative)
-- -1 = null
-- -2 = bool
-- -3 = nat
-- -4 = int
-- -5 = nat8
-- -6 = nat16
-- -7 = nat32
-- -8 = nat64
-- -9 = int8
-- -10 = int16
-- -11 = int32
-- -12 = int64
-- -13 = float32
-- -14 = float64
-- -15 = text
-- -16 = reserved
-- -17 = empty
-- -18 = opt
-- -19 = vec
-- -20 = record
-- -21 = variant
-- -22 = func
-- -23 = service
-- -24 = principal

TYPE_NAT : Int
TYPE_NAT = -3

TYPE_NAT8 : Int
TYPE_NAT8 = -5

TYPE_OPT : Int
TYPE_OPT = -18

TYPE_VEC : Int
TYPE_VEC = -19

TYPE_RECORD : Int
TYPE_RECORD = -20

TYPE_PRINCIPAL : Int
TYPE_PRINCIPAL = -24

-- =============================================================================
-- icrc1_balance_of Encoding
-- =============================================================================

||| Encode principal bytes for Candid
||| Principal is encoded as: tag (1 byte) + length (LEB128) + bytes
public export
encodePrincipal : List Bits8 -> List Bits8
encodePrincipal bytes =
  [0x01] ++ encodeNat (length bytes) ++ bytes

||| Encode optional blob (subaccount)
||| None = [0x00], Some = [0x01] + blob
public export
encodeOptBlob : Maybe (List Bits8) -> List Bits8
encodeOptBlob Nothing = [0x00]
encodeOptBlob (Just bs) = [0x01] ++ encodeBlob bs

||| Encode ICRC-1 Account record for icrc1_balance_of
|||
||| Account = record { owner : principal; subaccount : opt blob }
|||
||| Type table:
|||   0: record { owner: principal (-24), subaccount: opt vec nat8 }
|||   1: vec nat8
|||   2: opt (type 1)
|||
||| Field hashes (sorted):
|||   "owner" = 1158164430 (0x4510af4e)
|||   "subaccount" = 1970221089 (0x756b9541)
public export
encodeBalanceOfArg : Icrc1Account -> List Bits8
encodeBalanceOfArg acc =
  let -- Type table
      -- Type 0: vec nat8
      type0 = encodeInt TYPE_VEC ++ encodeInt TYPE_NAT8
      -- Type 1: opt (type 0)
      type1 = encodeInt TYPE_OPT ++ encodeNat 0  -- opt of type 0
      -- Type 2: record { owner: principal, subaccount: opt vec nat8 }
      -- Fields must be sorted by hash
      ownerHash = 1158164430       -- hash of "owner"
      subaccountHash = 1970221089  -- hash of "subaccount"
      type2 = encodeInt TYPE_RECORD
           ++ encodeNat 2  -- 2 fields
           ++ encodeNat (cast ownerHash) ++ encodeInt TYPE_PRINCIPAL
           ++ encodeNat (cast subaccountHash) ++ encodeNat 1  -- type 1 = opt vec nat8

      -- Full type table
      typeTable = encodeNat 3  -- 3 type definitions
               ++ type0
               ++ type1
               ++ type2

      -- Argument reference
      argTypes = encodeNat 1   -- 1 argument
              ++ encodeNat 2   -- type index 2 (the record)

      -- Value encoding
      -- Record values are encoded in field hash order
      ownerValue = encodePrincipal acc.owner
      subaccountValue = encodeOptBlob acc.subaccount
      values = ownerValue ++ subaccountValue

  in didlMagic ++ typeTable ++ argTypes ++ values

-- =============================================================================
-- icrc1_balance_of Response Decoding
-- =============================================================================

||| Decode Nat from Candid response
||| The response is: DIDL + type table + arg types + LEB128 nat value
|||
||| For a simple Nat response:
|||   DIDL (4 bytes)
|||   type_count = 0 (1 byte for LEB128)
|||   arg_count = 1 (1 byte)
|||   arg_type = -3 (nat) encoded as signed LEB128
|||   value = LEB128 nat
||| Decode LEB128 nat from bytes
decodeLeb128Nat : List Bits8 -> Nat
decodeLeb128Nat [] = 0
decodeLeb128Nat (b :: rest) =
  let val = cast {to=Nat} (b .&. 0x7F)
      hasMore = (b .&. 0x80) /= 0
  in if hasMore
     then val + 128 * decodeLeb128Nat rest
     else val

public export
decodeBalanceResponse : List Bits8 -> Maybe Nat
decodeBalanceResponse bytes =
  -- Check magic
  case splitAt 4 bytes of
    (magic, rest) =>
      if magic == didlMagic
        then decodeAfterMagic rest
        else Nothing
  where
    -- Skip type table and arg types, decode the nat value
    decodeAfterMagic : List Bits8 -> Maybe Nat
    decodeAfterMagic bs =
      -- Simple case: expect type_count=0, arg_count=1, arg_type=-3
      -- [0x00, 0x01, 0x7d] followed by LEB128 nat
      case bs of
        (0x00 :: 0x01 :: 0x7d :: valueBytes) =>
          Just (decodeLeb128Nat valueBytes)
        _ => Nothing

-- =============================================================================
-- Inter-Canister Call Helper Types
-- =============================================================================

||| Result of balance query
public export
data BalanceResult
  = BalanceOk Nat
  | BalanceError String

public export
Show BalanceResult where
  show (BalanceOk n) = "Balance: " ++ show n
  show (BalanceError e) = "Error: " ++ e

-- =============================================================================
-- ckETH Balance Sync Integration
-- =============================================================================

||| Build Candid payload for icrc1_balance_of call
||| To be used with ICP inter-canister call
public export
buildBalanceOfPayload : List Bits8 -> Maybe (List Bits8) -> List Bits8
buildBalanceOfPayload principal subaccount =
  encodeBalanceOfArg (MkIcrc1Account principal subaccount)

||| Method name for balance query
public export
METHOD_ICRC1_BALANCE_OF : String
METHOD_ICRC1_BALANCE_OF = "icrc1_balance_of"
