||| Lightweight Signature DTO
|||
||| Minimal data types for signature transport.
||| Avoids heavy MultiSig dependencies in downstream modules.
module OUC.Signatures

import Data.List

%default total

-- =============================================================================
-- Signature DTOs (no FRC, no complex logic)
-- =============================================================================

||| Aggregated signatures for upgrade execution
public export
record SignatureBundle where
  constructor MkSignatureBundle
  proposalId  : Nat
  proposerSig : String
  auditorSigs : List (String, String)  -- (auditorId, signature)

export
Show SignatureBundle where
  show s = "Sigs{proposal=" ++ show s.proposalId ++
           ", auditors=" ++ show (length s.auditorSigs) ++ "}"

||| Check if bundle has minimum signatures
export
hasMinSignatures : SignatureBundle -> Nat -> Bool
hasMinSignatures bundle minCount = length bundle.auditorSigs >= minCount
