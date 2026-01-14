||| DIDL (Candid Binary) Encoder
|||
||| Encodes Candid values to the DIDL binary format.
||| Reference: https://github.com/dfinity/candid/blob/master/spec/Candid.md
|||
||| DIDL format:
|||   "DIDL" (magic)
|||   + type_count (LEB128)
|||   + type_definitions...
|||   + arg_count (LEB128)
|||   + arg_type_indices...
|||   + values...
module Candid.Encoder

import Candid.Leb128
import Candid.Hash
import Data.Bits
import Data.List
import Data.String

%default total

-- =============================================================================
-- DIDL Magic Header
-- =============================================================================

||| DIDL magic bytes: "DIDL" = [0x44, 0x49, 0x44, 0x4C]
public export
didlMagic : List Bits8
didlMagic = [0x44, 0x49, 0x44, 0x4C]

-- =============================================================================
-- Candid Value Encoders
-- =============================================================================

||| Encode text value: LEB128 length + UTF-8 bytes
public export
encodeText : String -> List Bits8
encodeText s =
  let bytes = map (cast . ord) (unpack s)
      len = length bytes
  in encodeNat len ++ bytes

||| Encode nat64 value (fixed 8 bytes, little-endian)
public export
encodeNat64 : Bits64 -> List Bits8
encodeNat64 n =
  [ cast (n .&. 0xFF)
  , cast ((n `shiftR` 8) .&. 0xFF)
  , cast ((n `shiftR` 16) .&. 0xFF)
  , cast ((n `shiftR` 24) .&. 0xFF)
  , cast ((n `shiftR` 32) .&. 0xFF)
  , cast ((n `shiftR` 40) .&. 0xFF)
  , cast ((n `shiftR` 48) .&. 0xFF)
  , cast ((n `shiftR` 56) .&. 0xFF)
  ]

||| Encode blob value: LEB128 length + bytes
public export
encodeBlob : List Bits8 -> List Bits8
encodeBlob bs = encodeNat (length bs) ++ bs

-- =============================================================================
-- Variant Field Encoding
-- =============================================================================

||| A variant field: hash + type index
public export
record VariantField where
  constructor MkVariantField
  hash  : Bits32
  typeIdx : Int  -- Can be negative for primitive types

||| Encode a variant field: hash (LEB128 unsigned) + type (LEB128 signed)
public export
encodeVariantField : VariantField -> List Bits8
encodeVariantField f = encodeBits32 f.hash ++ encodeInt f.typeIdx

||| Create a variant field from name and type
public export
variantField : String -> Int -> VariantField
variantField name ty = MkVariantField (candidHash name) ty

-- =============================================================================
-- Type Table Builders
-- =============================================================================

||| Encode a variant type definition
||| Format: -21 (variant code) + field_count + sorted_fields
public export
encodeVariantType : List VariantField -> List Bits8
encodeVariantType fields =
  let sortedFields = sortBy (\a, b => compare a.hash b.hash) fields
  in encodeInt (-21) ++                        -- variant type code
     encodeNat (length sortedFields) ++        -- field count
     concatMap encodeVariantField sortedFields -- fields (sorted by hash)

||| Encode a simple type reference (type index)
public export
encodeTypeRef : Int -> List Bits8
encodeTypeRef = encodeInt

-- =============================================================================
-- DIDL Message Builder
-- =============================================================================

||| A complete DIDL message
public export
record DIDLMessage where
  constructor MkDIDL
  typeTable : List (List Bits8)  -- List of encoded type definitions
  argTypes  : List Int           -- Type indices for arguments (-ve for primitives)
  values    : List Bits8         -- Encoded values

||| Encode a complete DIDL message
public export
encodeDIDL : DIDLMessage -> List Bits8
encodeDIDL msg =
  didlMagic ++
  encodeNat (length msg.typeTable) ++       -- type count
  concat msg.typeTable ++                   -- type definitions
  encodeNat (length msg.argTypes) ++        -- arg count
  concatMap encodeInt msg.argTypes ++       -- arg type indices
  msg.values                                -- values

-- =============================================================================
-- Simple DIDL Constructors
-- =============================================================================

||| Empty DIDL response (no arguments)
public export
didlEmpty : List Bits8
didlEmpty = didlMagic ++ [0x00, 0x00]  -- 0 types, 0 args

||| DIDL with single text argument
public export
didlText : String -> List Bits8
didlText s = encodeDIDL $ MkDIDL
  []              -- no custom types
  [-15]           -- text type code
  (encodeText s)  -- text value

||| DIDL with single nat argument
public export
didlNat : Nat -> List Bits8
didlNat n = encodeDIDL $ MkDIDL
  []              -- no custom types
  [-3]            -- nat type code
  (encodeNat n)   -- nat value (unsigned LEB128)

-- =============================================================================
-- Debug Helpers
-- =============================================================================

||| Show DIDL message as hex dump
public export
showDIDL : List Bits8 -> String
showDIDL = showBytes
