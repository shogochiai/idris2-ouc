||| Relay Module
|||
||| Relays vote operations to OU contract on EVM via HttpOutcall.
||| OUC acts as a simple frontend - all voting logic lives in OU.
|||
||| Auditor mental model:
||| 1. Query OUC for assigned proposals
||| 2. Review the upgrade code
||| 3. Call OUC.vote(proposalId, decision)
||| 4. OUC handles all chain details
module OUC.Functions.Relay

import FRMonad.Core
import OUC.Functions.Core
import OUC.Types.Validated
import HttpOutcall.Core
import HttpOutcall.EvmRpc
import HttpOutcall.TxSender
import HttpOutcall.TxSender.Abi as Abi
import Data.List
import Data.String
import Data.Nat
import Util.StringHex as SHex

%default total

-- Safe division helper
safeDiv10 : Nat -> Nat
safeDiv10 n = divNatNZ n 10 ItIsSucc

-- =============================================================================
-- Decision Encoding
-- =============================================================================

||| Relay decision (matches OU contract uint8)
public export
data RelayDecision
  = RelayApprove
  | RelayReject
  | RelayRequestChanges

public export
Show RelayDecision where
  show RelayApprove        = "Approve"
  show RelayReject         = "Reject"
  show RelayRequestChanges = "RequestChanges"

||| Convert decision to uint8 for OU contract
decisionToInt : RelayDecision -> Nat
decisionToInt RelayApprove        = 1
decisionToInt RelayReject         = 2
decisionToInt RelayRequestChanges = 3

||| Convert ReviewDecision to RelayDecision
reviewToRelayDecision : ReviewDecision -> RelayDecision
reviewToRelayDecision ApproveUpgrade       = RelayApprove
reviewToRelayDecision (RejectUpgrade _)    = RelayReject
reviewToRelayDecision (RequestChanges _)   = RelayRequestChanges

||| Convert VoteDecision to RelayDecision
voteToRelayDecision : VoteDecision -> RelayDecision
voteToRelayDecision Approve              = RelayApprove
voteToRelayDecision (Reject _)           = RelayReject
voteToRelayDecision (RequestChanges _)   = RelayRequestChanges
voteToRelayDecision (Abstain _)          = RelayReject  -- Abstain treated as reject for contract

-- =============================================================================
-- Calldata Builders
-- =============================================================================

||| Helper: convert single hex digit
hexDigitChar : Integer -> Char
hexDigitChar d = if d < 10 then chr (ord '0' + cast d) else chr (ord 'a' + cast (d - 10))

||| Helper: convert integer to hex chars
partial
intToHexChars : Integer -> List Char
intToHexChars 0 = []
intToHexChars k = hexDigitChar (k `mod` 16) :: intToHexChars (k `div` 16)

||| Helper: convert nat to hex string
partial
natToHexStr : Nat -> String
natToHexStr 0 = "0"
natToHexStr n = pack $ reverse $ intToHexChars (cast n)

||| Encode uint256 using Integer div/mod (Nat doesn't have Integral)
partial
encodeUint256 : Nat -> String
encodeUint256 n = SHex.padTo32 (natToHexStr n)

||| Encode uint8 (0-255)
encodeUint8 : Nat -> String
encodeUint8 n =
  let i = cast {to=Integer} n
      hi = i `div` 16
      lo = i `mod` 16
  in SHex.padTo32 (pack [hexDigitChar hi, hexDigitChar lo])

||| Encode bytes32 (signature hash)
encodeBytes32 : String -> String
encodeBytes32 s = SHex.stripHexPrefix s

||| Build castVote calldata
||| castVote(uint256 proposalId, uint8 decision, bytes32 sigHash)
public export
partial
buildCastVoteCalldata : Nat -> RelayDecision -> String -> FR String
buildCastVoteCalldata proposalId decision sigHash =
  if sigHash == ""
    then fail Update "buildCastVoteCalldata" "Empty signature"
              (DecodeError "Signature hash required")
    else
      let calldata = Abi.SEL_CAST_VOTE
                  ++ encodeUint256 proposalId
                  ++ encodeUint8 (decisionToInt decision)
                  ++ encodeBytes32 sigHash
      in ok Update "buildCastVoteCalldata"
            ("Built castVote calldata for proposal " ++ show proposalId)
            calldata

||| Build submitProposerSignature calldata
public export
partial
buildProposerSigCalldata : Nat -> String -> FR String
buildProposerSigCalldata proposalId sigHash =
  if sigHash == ""
    then fail Update "buildProposerSigCalldata" "Empty signature"
              (DecodeError "Signature hash required")
    else
      let calldata = Abi.SEL_SUBMIT_PROPOSER_SIG
                  ++ encodeUint256 proposalId
                  ++ encodeBytes32 sigHash
      in ok Update "buildProposerSigCalldata"
            ("Built proposer sig calldata for proposal " ++ show proposalId)
            calldata

||| Build getVotingStatus calldata
public export
partial
buildGetStatusCalldata : Nat -> FR String
buildGetStatusCalldata proposalId =
  let calldata = Abi.SEL_GET_VOTING_STATUS ++ encodeUint256 proposalId
  in ok Query "buildGetStatusCalldata"
        ("Built getVotingStatus calldata for proposal " ++ show proposalId)
        calldata

-- =============================================================================
-- Voting Status (from OU)
-- =============================================================================

||| Voting status returned from OU contract
public export
record VotingStatus where
  constructor MkVotingStatus
  currentVotes   : Nat
  requiredVotes  : Nat
  isComplete     : Bool

public export
Show VotingStatus where
  show s = "VotingStatus{" ++ show s.currentVotes ++ "/" ++ show s.requiredVotes
        ++ ", complete=" ++ show s.isComplete ++ "}"

-- =============================================================================
-- Relay Operations (FRC-compliant)
-- =============================================================================

||| Relay vote to OU contract on EVM
||| This is the main entry point for auditors
public export
partial
relayVote :
  ChainTxConfig ->
  String ->           -- OU contract address
  Nat ->              -- proposalId
  RelayDecision ->
  String ->           -- signature hash
  Nat ->              -- nonce
  FR TxHash
relayVote config ouAddr proposalId decision sigHash nonce = do
  -- Build calldata
  calldata <- buildCastVoteCalldata proposalId decision sigHash

  -- Build transaction params
  let txParams = MkTxParams
        config.chainId
        nonce
        config.maxGasPrice
        (safeDiv10 config.maxGasPrice)
        config.defaultGasLimit
        ouAddr
        0
        calldata

  -- Note: Actual sending requires vetKey integration
  -- For now, return a placeholder indicating what would be sent
  fail Update "relayVote"
       ("Would send vote to OU at " ++ ouAddr ++ " on chain " ++ show config.chainId)
       (Internal "vetKey signing not yet implemented")

||| Relay proposer signature to OU contract
public export
partial
relayProposerSig :
  ChainTxConfig ->
  String ->           -- OU contract address
  Nat ->              -- proposalId
  String ->           -- signature hash
  Nat ->              -- nonce
  FR TxHash
relayProposerSig config ouAddr proposalId sigHash nonce = do
  calldata <- buildProposerSigCalldata proposalId sigHash

  let txParams = MkTxParams
        config.chainId
        nonce
        config.maxGasPrice
        (safeDiv10 config.maxGasPrice)
        config.defaultGasLimit
        ouAddr
        0
        calldata

  fail Update "relayProposerSig"
       ("Would send proposer sig to OU at " ++ ouAddr)
       (Internal "vetKey signing not yet implemented")

||| Query voting status from OU contract (via eth_call)
public export
partial
queryVotingStatus :
  ChainTxConfig ->
  String ->           -- OU contract address
  Nat ->              -- proposalId
  FR VotingStatus
queryVotingStatus config ouAddr proposalId = do
  calldata <- buildGetStatusCalldata proposalId

  -- Would call ethCall and parse result
  -- For now, return stub
  fail Query "queryVotingStatus"
       ("Would query status from OU at " ++ ouAddr)
       (Internal "ethCall not yet implemented")

-- =============================================================================
-- Auditor-Friendly API
-- =============================================================================

||| Proposal summary for auditor view
public export
record ProposalSummary where
  constructor MkProposalSummary
  id          : Nat
  description : String
  targetChain : String
  targetProxy : String
  newImpl     : String
  deadline    : Nat
  status      : String

public export
Show ProposalSummary where
  show p = "Proposal #" ++ show p.id ++ ": " ++ p.description
        ++ " (" ++ p.status ++ ")"

||| Vote result for auditor
public export
data VoteResult
  = VoteSubmitted TxHash
  | VotePending String       -- Waiting for tx confirmation
  | VoteFailed Fail

public export
Show VoteResult where
  show (VoteSubmitted h)  = "Vote submitted: " ++ show h
  show (VotePending msg)  = "Vote pending: " ++ msg
  show (VoteFailed f)     = "Vote failed: " ++ show f

||| Get proposals assigned to an auditor
||| Reads from local OUC state
public export
getAssignedProposals :
  OUCState ->
  AuditorId ->
  FR (List ProposalSummary)
getAssignedProposals state auditorId =
  let assigned = filter (isAssignedTo auditorId) state.proposals
      summaries = map toSummary assigned
  in ok Query "getAssignedProposals"
        ("Found " ++ show (length summaries) ++ " proposals for " ++ show auditorId)
        summaries
  where
    isAssignedTo : AuditorId -> Proposal -> Bool
    isAssignedTo aid prop = aid.principal `elem` prop.assignedAuditors

    toSummary : Proposal -> ProposalSummary
    toSummary p = MkProposalSummary
      p.proposalId
      ("Upgrade to " ++ evmAddressHex p.newImpl)
      ("Chain " ++ show p.chainId)
      (evmAddressHex p.target)
      (evmAddressHex p.newImpl)
      0  -- Would get from voting session
      (show p.state)

||| Submit vote for a proposal
||| Main entry point for auditors - hides all chain complexity
public export
partial
submitVote :
  OUCState ->
  AuditorId ->
  ProposalId ->
  ReviewDecision ->
  String ->           -- signature
  FR VoteResult
submitVote state auditorId proposalId decision sig = do
  -- Find proposal
  proposal <- findProposal state proposalId

  -- Get chain config
  let chainId = proposal.chainId
  case getChainConfig chainId of
    Nothing => fail Update "submitVote"
                    ("Unknown chain: " ++ show chainId)
                    (NotFound "Chain configuration not found")
    Just config => do
      -- Relay to OU
      -- Note: Would need to get OU address from proposal
      let ouAddr = evmAddressHex proposal.ou
      let relayDecision = reviewToRelayDecision decision

      -- Hash the signature for on-chain storage
      let sigHash = sig  -- In real impl, would hash

      -- Get nonce (would need to track per-chain)
      let nonce = 0

      result <- relayVote config ouAddr proposalId.value relayDecision sigHash nonce

      -- This will currently fail with "vetKey not implemented"
      -- When implemented, would return VoteSubmitted
      fail Update "submitVote" "Vote relay not yet implemented"
           (Internal "Full implementation pending vetKey integration")
