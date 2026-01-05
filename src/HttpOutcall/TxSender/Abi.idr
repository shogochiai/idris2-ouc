||| ABI Encoding for Transaction Calldata
|||
||| Function selectors and calldata construction.
||| Uses Util.StringHex, minimal FRC dependency.
module HttpOutcall.TxSender.Abi

import FRC.Core
import Util.StringHex
import Data.List

%default total

-- =============================================================================
-- OU Contract Function Selectors
-- =============================================================================

||| castVote(uint256,uint8,bytes32)
public export
SEL_CAST_VOTE : String
SEL_CAST_VOTE = "0x5c19a95c"

||| submitProposerSignature(uint256,bytes32)
public export
SEL_SUBMIT_PROPOSER_SIG : String
SEL_SUBMIT_PROPOSER_SIG = "0x7d4b1d9e"

||| getVotingStatus(uint256)
public export
SEL_GET_VOTING_STATUS : String
SEL_GET_VOTING_STATUS = "0x8a2c7b5e"

||| createProposal(uint256,address,address,bytes4,uint256)
public export
SEL_CREATE_PROPOSAL : String
SEL_CREATE_PROPOSAL = "0x3b2d5c8a"

||| executeUpgrade (legacy)
public export
SEL_EXECUTE_UPGRADE : String
SEL_EXECUTE_UPGRADE = "0x7b0472f0"

-- =============================================================================
-- ABI Encoding
-- =============================================================================

||| Encode address as 32-byte ABI parameter
export
encodeAddress : String -> String
encodeAddress addr = padTo32 addr

||| Build upgrade calldata
public export
buildUpgradeCalldata :
  String ->        -- proxy address
  String ->        -- new implementation
  String ->        -- proposer signature
  List String ->   -- auditor signatures
  FR String
buildUpgradeCalldata proxy newImpl proposerSig auditorSigs =
  if not (isHexPrefixed proxy) || length proxy /= 42
    then fail Update "buildUpgradeCalldata" "Invalid proxy address"
              (DecodeError "Proxy address format invalid")
    else if not (isHexPrefixed newImpl) || length newImpl /= 42
      then fail Update "buildUpgradeCalldata" "Invalid implementation address"
                (DecodeError "Implementation address format invalid")
      else
        let proxyEnc = encodeAddress proxy
            implEnc = encodeAddress newImpl
            calldata = SEL_EXECUTE_UPGRADE ++ proxyEnc ++ implEnc
        in ok Update "buildUpgradeCalldata"
              ("Built calldata: " ++ show (length calldata) ++ " chars")
              calldata
