||| Validated Address Types
module OUC.Types.Validated.Address

import Data.String

%default total

-- =============================================================================
-- Hex Character Validation
-- =============================================================================

||| Check if a character is a valid hex digit (0-9, a-f, A-F)
public export
isHexChar : Char -> Bool
isHexChar c = (c >= '0' && c <= '9') ||
              (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F')

||| Check if all characters in a string are hex digits
public export
allHex : String -> Bool
allHex s = all isHexChar (unpack s)

||| Normalize hex string to lowercase
public export
normalizeHex : String -> String
normalizeHex = toLower

-- =============================================================================
-- ValidatedEvmAddress: 40 hex characters, normalized to lowercase
-- =============================================================================

||| Opaque validated EVM address
export
data ValidatedEvmAddress : Type where
  MkValidatedEvmAddress : (hex : String) -> ValidatedEvmAddress

||| Smart constructor: validates format and normalizes
public export
mkEvmAddress : String -> Maybe ValidatedEvmAddress
mkEvmAddress s =
  let normalized = if isPrefixOf "0x" s || isPrefixOf "0X" s
                   then substr 2 (length s) s
                   else s
      lower = normalizeHex normalized
  in if length lower == 40 && allHex lower
     then Just (MkValidatedEvmAddress lower)
     else Nothing

||| Unsafe constructor for trusted internal use
export
unsafeMkEvmAddress : String -> ValidatedEvmAddress
unsafeMkEvmAddress = MkValidatedEvmAddress . normalizeHex

||| Get the raw hex string (without 0x prefix)
public export
evmAddressHex : ValidatedEvmAddress -> String
evmAddressHex (MkValidatedEvmAddress h) = h

||| Get with 0x prefix
public export
evmAddressWithPrefix : ValidatedEvmAddress -> String
evmAddressWithPrefix addr = "0x" ++ evmAddressHex addr

public export
Show ValidatedEvmAddress where
  show addr = evmAddressWithPrefix addr

public export
Eq ValidatedEvmAddress where
  a1 == a2 = evmAddressHex a1 == evmAddressHex a2

-- =============================================================================
-- ValidatedPrincipal: ICP Principal with format validation
-- =============================================================================

||| Validated ICP Principal
export
data ValidatedPrincipal : Type where
  MkValidatedPrincipal : (text : String) -> ValidatedPrincipal

||| Check if character is valid in base32 (ICP principal format)
isBase32Char : Char -> Bool
isBase32Char c = (c >= 'a' && c <= 'z') ||
                 (c >= '2' && c <= '7') ||
                 c == '-'

||| Smart constructor for principal
public export
mkPrincipal : String -> Maybe ValidatedPrincipal
mkPrincipal s =
  if length s >= 5 && all isBase32Char (unpack (toLower s))
  then Just (MkValidatedPrincipal (toLower s))
  else Nothing

||| Unsafe constructor for trusted input
export
unsafeMkPrincipal : String -> ValidatedPrincipal
unsafeMkPrincipal = MkValidatedPrincipal . toLower

public export
principalText : ValidatedPrincipal -> String
principalText (MkValidatedPrincipal t) = t

public export
Show ValidatedPrincipal where
  show p = principalText p

public export
Eq ValidatedPrincipal where
  p1 == p2 = principalText p1 == principalText p2
