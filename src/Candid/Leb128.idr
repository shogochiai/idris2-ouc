||| LEB128 (Little Endian Base 128) Encoding
|||
||| Variable-length encoding for integers used in Candid and WebAssembly.
||| - Unsigned LEB128: for positive integers (lengths, indices, hashes)
||| - Signed LEB128: for type codes (negative values like -21 for variant)
module Candid.Leb128

import Data.Bits
import Data.List

%default total

-- =============================================================================
-- Unsigned LEB128
-- =============================================================================

||| Encode unsigned integer as LEB128
||| Each byte uses 7 bits for data, high bit indicates continuation
public export
encodeUnsigned : Bits64 -> List Bits8
encodeUnsigned = go []
  where
    go : List Bits8 -> Bits64 -> List Bits8
    go acc 0 = if null acc then [0] else reverse acc
    go acc n =
      let byte = cast {to=Bits8} (n .&. 0x7F)
          rest = n `shiftR` 7
          byte' = if rest == 0 then byte else byte .|. 0x80
      in assert_total $ go (byte' :: acc) rest

||| Encode Nat as unsigned LEB128
public export
encodeNat : Nat -> List Bits8
encodeNat n = encodeUnsigned (cast n)

||| Encode Bits32 as unsigned LEB128 (for hashes)
public export
encodeBits32 : Bits32 -> List Bits8
encodeBits32 h = encodeUnsigned (cast {to=Bits64} h)

-- =============================================================================
-- Signed LEB128
-- =============================================================================

||| Encode signed integer as LEB128
||| Used for Candid type codes (e.g., -21 for variant, -19 for vec)
public export
encodeSigned : Int64 -> List Bits8
encodeSigned = go []
  where
    go : List Bits8 -> Int64 -> List Bits8
    go acc n =
      let byte : Bits8 = cast {to=Bits8} (cast {to=Bits64} n .&. 0x7F)
          rest = n `shiftR` 7
          signBit = (byte .&. 0x40) /= 0
          done = (rest == 0 && not signBit) || (rest == -1 && signBit)
          contBit : Bits8 = 0x80
          byte' : Bits8 = if done then byte else byte .|. contBit
      in if done
         then reverse (byte' :: acc)
         else assert_total $ go (byte' :: acc) rest

||| Encode Int as signed LEB128
public export
encodeInt : Int -> List Bits8
encodeInt n = encodeSigned (cast n)

-- =============================================================================
-- Candid Type Codes (signed LEB128)
-- =============================================================================

||| Candid primitive type codes
public export
data CandidType
  = TNull      -- -1
  | TBool      -- -2
  | TNat       -- -3
  | TInt       -- -4
  | TNat8      -- -5
  | TNat16     -- -6
  | TNat32     -- -7
  | TNat64     -- -8
  | TInt8      -- -9
  | TInt16     -- -10
  | TInt32     -- -11
  | TInt64     -- -12
  | TFloat32   -- -13
  | TFloat64   -- -14
  | TText      -- -15
  | TReserved  -- -16
  | TEmpty     -- -17
  | TPrincipal -- -24
  | TVec       -- -19 (followed by element type)
  | TOpt       -- -18 (followed by element type)
  | TRecord    -- -20 (followed by fields)
  | TVariant   -- -21 (followed by fields)

||| Get the numeric type code
public export
typeCode : CandidType -> Int
typeCode TNull      = -1
typeCode TBool      = -2
typeCode TNat       = -3
typeCode TInt       = -4
typeCode TNat8      = -5
typeCode TNat16     = -6
typeCode TNat32     = -7
typeCode TNat64     = -8
typeCode TInt8      = -9
typeCode TInt16     = -10
typeCode TInt32     = -11
typeCode TInt64     = -12
typeCode TFloat32   = -13
typeCode TFloat64   = -14
typeCode TText      = -15
typeCode TReserved  = -16
typeCode TEmpty     = -17
typeCode TPrincipal = -24
typeCode TVec       = -19
typeCode TOpt       = -18
typeCode TRecord    = -20
typeCode TVariant   = -21

||| Encode a Candid type code
public export
encodeTypeCode : CandidType -> List Bits8
encodeTypeCode = encodeInt . typeCode

-- =============================================================================
-- Utility: List Bits8 -> packed bytes
-- =============================================================================

||| Hex character for 0-15
hexChar : Integer -> Char
hexChar n = if n < 10 then chr (cast n + ord '0') else chr (cast (n - 10) + ord 'A')

||| Convert byte to 2-char hex string
byteToHex : Bits8 -> String
byteToHex b =
  let hi = cast {to=Integer} (b `shiftR` 4)
      lo = cast {to=Integer} (b .&. 0x0F)
  in pack [hexChar hi, hexChar lo]

||| Convert list of bytes to a compact representation for debugging
public export
showBytes : List Bits8 -> String
showBytes bs = "[" ++ concat (intersperse ", " (map (\b => "0x" ++ byteToHex b) bs)) ++ "]"
