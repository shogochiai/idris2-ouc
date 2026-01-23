||| Validated Signature Types
module OUC.Types.Validated.Signature

import Data.String
import OUC.Types.Validated.Address

%default total

-- =============================================================================
-- Signature Validation
-- =============================================================================

||| Validated ECDSA signature (65 bytes = 130 hex chars)
export
data ValidatedSignature : Type where
  MkValidatedSignature : (hex : String) -> ValidatedSignature

||| Smart constructor for signature
public export
mkSignature : String -> Maybe ValidatedSignature
mkSignature s =
  let normalized = if isPrefixOf "0x" s then substr 2 (length s) s else s
      lower = normalizeHex normalized
  in if (length lower == 130 || length lower == 128) && allHex lower
     then Just (MkValidatedSignature lower)
     else Nothing

||| Get signature hex
public export
signatureHex : ValidatedSignature -> String
signatureHex (MkValidatedSignature h) = h

public export
Show ValidatedSignature where
  show sig = "0x" ++ signatureHex sig

public export
Eq ValidatedSignature where
  s1 == s2 = signatureHex s1 == signatureHex s2
