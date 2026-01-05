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
module OUC.Relay

import FRC.Core
import OUC.Core
import HttpOutcall.Core
import HttpOutcall.EvmRpc
import HttpOutcall.TxSender
import Data.List
import Data.String
import Util.StringHex as SHex

%default total

-- =============================================================================
-- OU Contract Selectors
-- =============================================================================

||| castVote(uint256,uint8,bytes32)
SEL_CAST_VOTE : String
SEL_CAST_VOTE = "0x5c19a95c"

||| submitProposerSignature(uint256,bytes32)
SEL_SUBMIT_PROPOSER_SIG : String
SEL_SUBMIT_PROPOSER_SIG = "0x7d4b1d9e"

||| getVotingStatus(uint256)
SEL_GET_VOTING_STATUS : String
SEL_GET_VOTING_STATUS = "0x8a2c7b5e"

||| createProposal(uint256,address,address,bytes4,uint256)
SEL_CREATE_PROPOSAL : String
SEL_CREATE_PROPOSAL = "0x3b2d5c8a"

-- =============================================================================
-- Decision Encoding
-- =============================================================================

||| Vote decision (matches OU contract)
public export
data VoteDecision
  = Approve
  | Reject
  | RequestChanges

public export
Show VoteDecision where
  show Approve        = "Approve"
  show Reject         = "Reject"
  show RequestChanges = "RequestChanges"

||| Convert decision to uint8 for OU contract
decisionToInt : VoteDecision -> Nat
decisionToInt Approve        = 1
decisionToInt Reject         = 2
decisionToInt RequestChanges = 3

||| Convert ReviewDecision to VoteDecision
reviewToVoteDecision : ReviewDecision -> VoteDecision
reviewToVoteDecision ApproveUpgrade       = Approve
reviewToVoteDecision (RejectUpgrade _)    = Reject
reviewToVoteDecision (RequestChanges _)   = RequestChanges

-- =============================================================================
-- Calldata Builders
-- =============================================================================

||| Encode uint256 using Integer div/mod (Nat doesn't have Integral)
encodeUint256 : Nat -> String
encodeUint256 n = SHex.padTo32 (natToHex n)
  where
    hexDigit : Integer -> Char
    hexDigit d = if d < 10 then chr (ord '0' + cast d) else chr (ord 'a' + cast (d - 10))

    natToHex : Nat -> String
    natToHex 0 = "0"
    natToHex n = pack $ reverse $ go (cast n)
      where
        go : Integer -> List Char
        go 0 = []
        go k = hexDigit (k `mod` 16) :: go (k `div` 16)

||| Encode uint8 (0-255)
encodeUint8 : Nat -> String
encodeUint8 n =
  let i = cast {to=Integer} n
      hi = i `div` 16
      lo = i `mod` 16
  in SHex.padTo32 (pack [hexChar hi, hexChar lo])
  where
    hexChar : Integer -> Char
    hexChar d = if d < 10 then chr (ord '0' + cast d) else chr (ord 'a' + cast (d - 10))

||| Encode bytes32 (signature hash)
encodeBytes32 : String -> String
encodeBytes32 s = SHex.stripHexPrefix s

||| Build castVote calldata
||| castVote(uint256 proposalId, uint8 decision, bytes32 sigHash)
public export
buildCastVoteCalldata : Nat -> VoteDecision -> String -> FR String
buildCastVoteCalldata proposalId decision sigHash =
  if sigHash == ""
    then fail Update "buildCastVoteCalldata" "Empty signature"
              (DecodeError "Signature hash required")
    else
      let calldata = SEL_CAST_VOTE
                  ++ encodeUint256 proposalId
                  ++ encodeUint8 (decisionToInt decision)
                  ++ encodeBytes32 sigHash
      in ok Update "buildCastVoteCalldata"
            ("Built castVote calldata for proposal " ++ show proposalId)
            calldata

||| Build submitProposerSignature calldata
public export
buildProposerSigCalldata : Nat -> String -> FR String
buildProposerSigCalldata proposalId sigHash =
  if sigHash == ""
    then fail Update "buildProposerSigCalldata" "Empty signature"
              (DecodeError "Signature hash required")
    else
      let calldata = SEL_SUBMIT_PROPOSER_SIG
                  ++ encodeUint256 proposalId
                  ++ encodeBytes32 sigHash
      in ok Update "buildProposerSigCalldata"
            ("Built proposer sig calldata for proposal " ++ show proposalId)
            calldata

||| Build getVotingStatus calldata
public export
buildGetStatusCalldata : Nat -> FR String
buildGetStatusCalldata proposalId =
  let calldata = SEL_GET_VOTING_STATUS ++ encodeUint256 proposalId
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
relayVote :
  ChainTxConfig ->
  String ->           -- OU contract address
  Nat ->              -- proposalId
  VoteDecision ->
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
        (config.maxGasPrice `div` 10)
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
        (config.maxGasPrice `div` 10)
        config.defaultGasLimit
        ouAddr
        0
        calldata

  fail Update "relayProposerSig"
       ("Would send proposer sig to OU at " ++ ouAddr)
       (Internal "vetKey signing not yet implemented")

||| Query voting status from OU contract (via eth_call)
public export
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
  | VoteFailed IcpFail

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
    isAssignedTo : AuditorId -> UpgradeProposal -> Bool
    isAssignedTo aid prop = aid `elem` prop.assignedAuditors

    toSummary : UpgradeProposal -> ProposalSummary
    toSummary p = MkProposalSummary
      (cast p.id)  -- Convert ProposalId to Nat
      ("Upgrade to " ++ p.newImpl.hex)
      ("Chain " ++ show p.chainId.value)
      p.target.hex
      p.newImpl.hex
      0  -- Would get from voting session
      (show p.status)

||| Submit vote for a proposal
||| Main entry point for auditors - hides all chain complexity
public export
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
  case getChainConfig proposal.chainId.value of
    Nothing => fail Update "submitVote"
                    ("Unknown chain: " ++ show proposal.chainId.value)
                    (NotFound "Chain configuration not found")
    Just config => do
      -- Relay to OU
      -- Note: Would need to get OU address from proposal
      let ouAddr = proposal.ou.hex
      let voteDecision = reviewToVoteDecision decision

      -- Hash the signature for on-chain storage
      let sigHash = sig  -- In real impl, would hash

      -- Get nonce (would need to track per-chain)
      let nonce = 0

      result <- relayVote config ouAddr (cast proposalId) voteDecision sigHash nonce

      -- This will currently fail with "vetKey not implemented"
      -- When implemented, would return VoteSubmitted
      fail Update "submitVote" "Vote relay not yet implemented"
           (Internal "Full implementation pending vetKey integration")
