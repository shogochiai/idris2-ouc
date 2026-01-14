||| Candid Variant/Record Field Hash Function
|||
||| Implements the Candid specification hash for variant and record field names.
||| Reference: https://github.com/dfinity/candid/blob/master/spec/Candid.md
|||
||| hash(id) = ( Σ id[i] * 223^(n-1-i) ) mod 2^32
|||
||| This is used to:
||| - Sort variant options by hash (ascending) to determine their index
||| - Encode field names in the type table
module Candid.Hash

import Data.Bits
import Data.List
import Data.String

%default total

-- =============================================================================
-- Core Hash Function
-- =============================================================================

||| Candid hash function for field/variant names
|||
||| The hash is computed as a polynomial rolling hash:
|||   h = 0
|||   for each char c in name:
|||     h = (h * 223 + ord(c)) mod 2^32
|||
||| @ name The field or variant name to hash
public export
candidHash : String -> Bits32
candidHash name = foldl step 0 (unpack name)
  where
    step : Bits32 -> Char -> Bits32
    step h c = h * 223 + cast (ord c)

-- =============================================================================
-- Utility Functions
-- =============================================================================

||| Convert char to uppercase
toUpperChar : Char -> Char
toUpperChar c = if c >= 'a' && c <= 'f'
                then chr (ord c - 32)
                else c

||| Convert string to uppercase
toUpperStr : String -> String
toUpperStr = pack . map toUpperChar . unpack

||| Pad string on the left to specified width
padLeftStr : Nat -> Char -> String -> String
padLeftStr n c s = let len = length s
                   in if len >= n
                      then s
                      else pack (replicate (minus n len) c) ++ s

||| Hex digit for 0-15
hexDigit : Integer -> Char
hexDigit d = if d < 10
             then chr (cast d + ord '0')
             else chr (cast (d - 10) + ord 'a')

||| Convert integer to hex string (partial - only used for display)
partial
intToHexGo : Integer -> String -> String
intToHexGo 0 acc = acc
intToHexGo m acc = intToHexGo (m `div` 16) (singleton (hexDigit (m `mod` 16)) ++ acc)

||| Convert integer to hex string
intToHex : Integer -> String
intToHex n = if n == 0 then "0" else assert_total (intToHexGo n "")

||| Format hash as hex string (for debugging/display)
public export
hashToHex : Bits32 -> String
hashToHex h = "0x" ++ toUpperStr (padLeftStr 8 '0' (intToHex (cast {to=Integer} h)))

||| Compare two names by their Candid hash (for sorting)
public export
compareByHash : String -> String -> Ordering
compareByHash a b = compare (candidHash a) (candidHash b)

||| Sort a list of names by Candid hash (ascending)
||| This is how Candid orders variant options
public export
sortByHash : List String -> List String
sortByHash = sortBy compareByHash

||| Get the index of a name in a hash-sorted list of names
||| Returns Nothing if name is not in the list
public export
hashIndex : String -> List String -> Maybe Nat
hashIndex name names = map finToNat (findIndex (== name) (sortByHash names))

-- =============================================================================
-- Known Hashes (for reference and testing)
-- =============================================================================

-- These are the expected hashes from the EVM RPC canister.
-- They should match what's hardcoded in canister_entry.c

||| EVM RPC Chain names
public export
evmRpcChains : List String
evmRpcChains = ["EthMainnet", "EthSepolia", "BaseMainnet", "ArbitrumOne"]

||| EVM RPC Service Provider names
public export
evmRpcProviders : List String
evmRpcProviders = ["Alchemy", "Ankr", "BlockPi", "Cloudflare", "PublicNode", "Llama"]
