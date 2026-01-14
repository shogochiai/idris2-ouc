||| Auditor Assignment and Execution Operations
|||
||| ABI encoding for OUC → OU Contract cross-chain transactions:
||| - assignAuditors: OUC assigns auditors to proposals
||| - executeApproved: OUC triggers execution when threshold reached
|||
||| These txs are signed via t-ECDSA and submitted via HTTP Outcall.
module HttpOutcall.TxSender.AuditorOps

import FRMonad.Core
import HttpOutcall.TxSender.Types
import HttpOutcall.TxSender.Abi
import OUC.Functions.Core
import Util.StringHex
import Data.List
import Data.Nat

%default covering

-- =============================================================================
-- OU Contract Function Selectors (Auditor Operations)
-- =============================================================================

||| assignAuditors(uint256 proposalId, address[] auditors)
||| Selector: keccak256("assignAuditors(uint256,address[])")[:4]
public export
SEL_ASSIGN_AUDITORS : String
SEL_ASSIGN_AUDITORS = "0x4a7702bb"

||| executeApproved(uint256 proposalId)
||| Selector: keccak256("executeApproved(uint256)")[:4]
public export
SEL_EXECUTE_APPROVED : String
SEL_EXECUTE_APPROVED = "0x791a2519"

||| getProposal(uint256 proposalId)
||| Read-only call to get proposal state
public export
SEL_GET_PROPOSAL : String
SEL_GET_PROPOSAL = "0xc7f758a8"

-- =============================================================================
-- ABI Encoding Helpers
-- =============================================================================

||| Convert Nat to hex string (without 0x prefix)
||| Uses divNatNZ and modNatNZ with proof of 16 /= 0
natToHexHelper : Nat -> List Char -> List Char
natToHexHelper 0 []  = ['0']
natToHexHelper 0 acc = acc
natToHexHelper n acc =
  let digit = modNatNZ n 16 ItIsSucc
      rest = divNatNZ n 16 ItIsSucc
      c = if digit < 10
            then chr (cast digit + ord '0')
            else chr (cast (digit `minus` 10) + ord 'a')
  in natToHexHelper rest (c :: acc)

natToHex : Nat -> String
natToHex n = pack (natToHexHelper n [])

||| Encode uint256 as 32-byte ABI parameter (local to this module)
encodeUint256Local : Nat -> String
encodeUint256Local n = padTo32 (natToHex n)

||| Encode dynamic array of addresses
||| Layout: offset (32) + length (32) + addresses (32 each)
encodeAddressArray : List String -> FR String
encodeAddressArray addrs =
  let validAddrs = filter (\a => isHexPrefixed a && length a == 42) addrs
  in if length validAddrs /= length addrs
    then fail Update "encodeAddressArray" "Invalid address in list"
              (DecodeError "All addresses must be 0x + 40 hex chars")
    else
      let offset = "0000000000000000000000000000000000000000000000000000000000000040"  -- 64 in hex
          len = padTo32 (natToHex (length addrs))
          encodedAddrs = concat (map encodeAddress addrs)
      in ok Update "encodeAddressArray"
            ("Encoded " ++ show (length addrs) ++ " addresses")
            (offset ++ len ++ encodedAddrs)

-- =============================================================================
-- Calldata Builders
-- =============================================================================

||| Build assignAuditors calldata
||| OUC calls this to assign auditors to a proposal on OU Contract
public export
buildAssignAuditorsCalldata :
  Nat ->              -- proposalId
  List String ->      -- auditor EVM addresses
  FR String
buildAssignAuditorsCalldata proposalId auditorAddrs =
  if length auditorAddrs == 0
    then fail Update "buildAssignAuditorsCalldata" "No auditors to assign"
              (InvalidState "Auditor list cannot be empty")
    else do
      encodedArray <- encodeAddressArray auditorAddrs
      let encodedProposalId = encodeUint256Local proposalId
          calldata = SEL_ASSIGN_AUDITORS ++ encodedProposalId ++ encodedArray
      ok Update "buildAssignAuditorsCalldata"
         ("Built assignAuditors calldata for proposal " ++ show proposalId)
         calldata

||| Build executeApproved calldata
||| OUC calls this when vote threshold is reached
public export
buildExecuteApprovedCalldata :
  Nat ->              -- proposalId
  FR String
buildExecuteApprovedCalldata proposalId =
  let encodedProposalId = encodeUint256Local proposalId
      calldata = SEL_EXECUTE_APPROVED ++ encodedProposalId
  in ok Update "buildExecuteApprovedCalldata"
        ("Built executeApproved calldata for proposal " ++ show proposalId)
        calldata

||| Build getProposal calldata (read-only)
public export
buildGetProposalCalldata :
  Nat ->              -- proposalId
  String
buildGetProposalCalldata proposalId =
  SEL_GET_PROPOSAL ++ encodeUint256Local proposalId

-- =============================================================================
-- Transaction Parameter Builders
-- =============================================================================

||| Parameters for auditor assignment tx
public export
record AssignAuditorsParams where
  constructor MkAssignAuditorsParams
  chainConfig    : ChainTxConfig
  ouAddress      : String       -- OU Contract address
  proposalId     : Nat
  auditorAddrs   : List String  -- EVM addresses of assigned auditors
  nonce          : Nat
  maxGasPrice    : Nat

export
Show AssignAuditorsParams where
  show p = "AssignAuditors{ou=" ++ p.ouAddress
        ++ ", proposal=" ++ show p.proposalId
        ++ ", auditors=" ++ show (length p.auditorAddrs) ++ "}"

||| Validate assign auditors parameters
public export
validateAssignParams : AssignAuditorsParams -> FR ()
validateAssignParams params =
  if not (isHexPrefixed params.ouAddress) || length params.ouAddress /= 42
    then fail Update "validateAssignParams" "Invalid OU address"
              (DecodeError "OU address format invalid")
    else if length params.auditorAddrs == 0
      then fail Update "validateAssignParams" "No auditors specified"
                (InvalidState "Must assign at least one auditor")
      else if params.maxGasPrice > params.chainConfig.maxGasPrice
        then fail Update "validateAssignParams" "Gas price too high"
                  (InvalidState "Exceeds chain limit")
        else ok Update "validateAssignParams" "Valid" ()

||| Parameters for execute approved tx
public export
record ExecuteApprovedParams where
  constructor MkExecuteApprovedParams
  chainConfig    : ChainTxConfig
  ouAddress      : String       -- OU Contract address
  proposalId     : Nat
  nonce          : Nat
  maxGasPrice    : Nat

export
Show ExecuteApprovedParams where
  show p = "ExecuteApproved{ou=" ++ p.ouAddress
        ++ ", proposal=" ++ show p.proposalId ++ "}"

||| Validate execute approved parameters
public export
validateExecuteParams : ExecuteApprovedParams -> FR ()
validateExecuteParams params =
  if not (isHexPrefixed params.ouAddress) || length params.ouAddress /= 42
    then fail Update "validateExecuteParams" "Invalid OU address"
              (DecodeError "OU address format invalid")
    else if params.maxGasPrice > params.chainConfig.maxGasPrice
      then fail Update "validateExecuteParams" "Gas price too high"
                (InvalidState "Exceeds chain limit")
      else ok Update "validateExecuteParams" "Valid" ()

-- =============================================================================
-- Transaction Preparation (pre-signing)
-- =============================================================================

||| Prepare assignAuditors tx for signing
||| Returns: (to address, calldata, gas limit)
public export
prepareAssignAuditorsTx :
  AssignAuditorsParams ->
  FR (String, String, Nat)
prepareAssignAuditorsTx params = do
  validateAssignParams params
  calldata <- buildAssignAuditorsCalldata params.proposalId params.auditorAddrs
  -- Gas estimate: base + per-address storage
  let gasLimit = params.chainConfig.defaultGasLimit + (length params.auditorAddrs * 25000)
  ok Update "prepareAssignAuditorsTx"
     ("Prepared tx to " ++ params.ouAddress)
     (params.ouAddress, calldata, gasLimit)

||| Prepare executeApproved tx for signing
||| Returns: (to address, calldata, gas limit)
public export
prepareExecuteApprovedTx :
  ExecuteApprovedParams ->
  FR (String, String, Nat)
prepareExecuteApprovedTx params = do
  validateExecuteParams params
  calldata <- buildExecuteApprovedCalldata params.proposalId
  -- Execute typically needs more gas for state changes
  let gasLimit = params.chainConfig.defaultGasLimit * 2
  ok Update "prepareExecuteApprovedTx"
     ("Prepared tx to " ++ params.ouAddress)
     (params.ouAddress, calldata, gasLimit)

-- =============================================================================
-- Integration with Vote Module
-- =============================================================================

||| Check if execution should be triggered
||| Called after vote is recorded to determine if threshold reached
public export
shouldTriggerExecution : Bool -> Bool
shouldTriggerExecution approvalReached = approvalReached

||| Auditor Principal to EVM address mapping
||| In production, this would look up registered EVM addresses
||| For now, returns placeholder (actual mapping stored in canister state)
public export
auditorPrincipalToEvmAddr : ICPrincipal -> Maybe String
auditorPrincipalToEvmAddr principal =
  -- TODO: Lookup from registered auditor mapping
  -- Each auditor registers their EVM address when joining pool
  Nothing
