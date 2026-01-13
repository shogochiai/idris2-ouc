||| String Hex Utilities
|||
||| Shared hex string manipulation for EVM/ICP interop.
||| Uses unpack/pack to avoid substr bugs and replicate OOM.
module Util.StringHex

import Data.String
import Data.List
import Data.Bits

%default total

-- =============================================================================
-- Hex Prefix Handling (unpack/pack based - total & boundary safe)
-- =============================================================================

||| Check if string starts with "0x" (pattern match, no substr)
public export
isHexPrefixed : String -> Bool
isHexPrefixed s =
  case unpack s of
    '0' :: 'x' :: _ => True
    _               => False

||| Strip "0x" prefix (pattern match, no substr/drop)
public export
stripHexPrefix : String -> String
stripHexPrefix s =
  case unpack s of
    '0' :: 'x' :: cs => pack cs
    _                => s

-- =============================================================================
-- Zero Padding (OOM-safe, no replicate)
-- =============================================================================

||| Precomputed 64 zeros (32 bytes in hex)
public export
zeros64 : String
zeros64 = "0000000000000000000000000000000000000000000000000000000000000000"

||| Precomputed as List Char for safe take
zeros64List : List Char
zeros64List = unpack zeros64

||| Take first n zeros (using List.take, total)
public export
takeZeros : Nat -> String
takeZeros n = pack (take n zeros64List)

||| Pad hex to 32 bytes (64 hex chars), left-padded with zeros
public export
padTo32 : String -> String
padTo32 s =
  let stripped = stripHexPrefix s
      len = length stripped
      padLen = if len >= 64 then 0 else 64 `minus` len
  in takeZeros padLen ++ stripped

-- =============================================================================
-- Address/Selector Validation
-- =============================================================================

||| Validate Ethereum address format (0x + 40 hex chars)
public export
isValidAddress : String -> Bool
isValidAddress s = isHexPrefixed s && length s == 42

||| Validate function selector format (0x + 8 hex chars)
public export
isValidSelector : String -> Bool
isValidSelector s = isHexPrefixed s && length s == 10

||| Validate tx hash format (0x + 64 hex chars)
public export
isValidTxHash : String -> Bool
isValidTxHash s = isHexPrefixed s && length s == 66

-- =============================================================================
-- Hex <-> Bytes Conversion
-- =============================================================================

||| Convert hex char to nibble (0-15)
hexCharToNibble : Char -> Bits8
hexCharToNibble c =
  if c >= '0' && c <= '9' then cast (ord c - ord '0')
  else if c >= 'a' && c <= 'f' then cast (ord c - ord 'a' + 10)
  else if c >= 'A' && c <= 'F' then cast (ord c - ord 'A' + 10)
  else 0

||| Convert nibble to hex char
nibbleToHexChar : Bits8 -> Char
nibbleToHexChar n =
  if n < 10 then chr (cast n + ord '0')
  else chr (cast (n - 10) + ord 'a')

||| Convert pairs of hex chars to bytes
hexPairsToBytes : List Char -> List Bits8
hexPairsToBytes [] = []
hexPairsToBytes [_] = []  -- odd length, ignore trailing
hexPairsToBytes (h :: l :: rest) =
  let hi = hexCharToNibble h
      lo = hexCharToNibble l
  in (hi * 16 + lo) :: hexPairsToBytes rest

||| Convert hex string to bytes (strips 0x prefix if present)
public export
hexToBytes : String -> List Bits8
hexToBytes s = hexPairsToBytes (unpack (stripHexPrefix s))

||| Convert byte to two hex chars
byteToHexChars : Bits8 -> List Char
byteToHexChars b =
  [ nibbleToHexChar (b `div` 16)
  , nibbleToHexChar (b `mod` 16)
  ]

||| Convert bytes to hex string (without 0x prefix)
public export
bytesToHex : List Bits8 -> String
bytesToHex bs = pack (concatMap byteToHexChars bs)
