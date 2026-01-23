||| ERC-7546 Upgrade Module
|||
||| Orchestrates the full upgrade execution flow:
||| 1. Validate proposal and signatures
||| 2. Build dictionary update calldata
||| 3. Execute via OU contract with n-of-n multisig
||| 4. Verify execution result on-chain
module ERC7546.Upgrade

import FRMonad.Core
import OUC.Functions.Core
import OUC.Types.Validated
import OUC.Functions.MultiSig
import OUC.Functions.Signatures
import HttpOutcall.Core
import HttpOutcall.EvmRpc
import HttpOutcall.TxSender
import ERC7546.Dictionary
import Data.List
import Data.Maybe

%default total

-- =============================================================================
-- Type Conversion Helpers
-- =============================================================================

||| Convert AggregatedSignatures to SignatureBundle for execution
toSignatureBundle : AggregatedSignatures -> SignatureBundle
toSignatureBundle agg = MkSignatureBundle
  agg.proposalId.value
  agg.proposerSig
  (map (\(aid, sig) => (principalText aid.principal, sig)) agg.auditorSigs)

-- =============================================================================
-- Upgrade Execution Types
-- =============================================================================

||| Complete upgrade request with all required data
||| Proposal must be in Approved state (checked at runtime)
public export
record UpgradeRequest where
  constructor MkUpgradeRequest
  proposal    : Proposal           -- Must be in SApproved state
  voting      : VotingSession
  signatures  : AggregatedSignatures
  chainConfig : ChainTxConfig
  nonce       : Nat
  maxGasPrice : Nat
  deadline    : Nat                -- Execution deadline (IC timestamp)

public export
Show UpgradeRequest where
  show r = "UpgradeRequest{proposal=" ++ show r.proposal.proposalId ++
           ", chain=" ++ show r.chainConfig.chainId ++ "}"

||| Upgrade execution result
public export
data UpgradeResult
  = UpgradeSuccess TxReceipt
  | UpgradeReverted String TxReceipt
  | UpgradeTimeout TxHash
  | UpgradeRejected String         -- Proposal was rejected
  | UpgradeFailed Fail

public export
Show UpgradeResult where
  show (UpgradeSuccess r)    = "Success: " ++ show r.txHash
  show (UpgradeReverted s r) = "Reverted: " ++ s ++ " (tx=" ++ show r.txHash ++ ")"
  show (UpgradeTimeout h)    = "Timeout: " ++ show h
  show (UpgradeRejected s)   = "Rejected: " ++ s
  show (UpgradeFailed f)     = "Failed: " ++ show f

||| Check if upgrade was successful
public export
isUpgradeSuccess : UpgradeResult -> Bool
isUpgradeSuccess (UpgradeSuccess _) = True
isUpgradeSuccess _ = False

-- =============================================================================
-- Upgrade Validation
-- =============================================================================

||| Validate upgrade request before execution
||| Note: Status check is no longer needed - type system enforces Approved status
public export
validateUpgradeRequest :
  UpgradeRequest ->
  Nat ->              -- currentTime
  FR ()
validateUpgradeRequest req now = do
  -- Check proposal is approved
  if req.proposal.state /= SApproved
    then fail Update "validateUpgradeRequest" "Proposal not approved"
              (InvalidState ("Expected Approved, got " ++ show req.proposal.state))
    else pure ()

  -- Check deadline
  if now > req.deadline
    then fail Update "validateUpgradeRequest" "Execution deadline passed"
              (Timeout ("Deadline: " ++ show req.deadline ++ ", now: " ++ show now))
    else pure ()

  -- Check chain ID matches
  if req.proposal.chainId /= req.chainConfig.chainId
    then fail Update "validateUpgradeRequest"
              ("Chain mismatch: proposal=" ++ show req.proposal.chainId ++
               ", config=" ++ show req.chainConfig.chainId)
              (InvalidState "Chain ID mismatch")
    else pure ()

  -- Check signatures match proposal
  if req.signatures.proposalId.value /= req.proposal.proposalId
    then fail Update "validateUpgradeRequest"
              "Signatures are for different proposal"
              (InvalidState "Signature/proposal ID mismatch")
    else pure ()

  -- Verify signature count meets threshold
  verifySignatureCount req.signatures

  ok Update "validateUpgradeRequest" "All validations passed" ()

-- =============================================================================
-- Upgrade Calldata Construction
-- =============================================================================

||| Build complete upgrade calldata for OU contract
public export
buildCompleteUpgradeCalldata :
  UpgradeRequest ->
  FR String
buildCompleteUpgradeCalldata req = do
  -- Get base upgrade calldata
  baseCalldata <- buildUpgradeTo (evmAddressHex req.proposal.newImpl)

  -- Build full OU.executeUpgrade calldata
  buildUpgradeCalldata
    (evmAddressHex req.proposal.target)
    (evmAddressHex req.proposal.newImpl)
    req.signatures.proposerSig
    (map snd req.signatures.auditorSigs)

-- =============================================================================
-- Upgrade Execution Flow
-- =============================================================================

||| Execute upgrade via OptimisticUpgrader contract
public export
executeUpgradeViaOU :
  UpgradeRequest ->
  Nat ->              -- currentTime
  FR UpgradeResult
executeUpgradeViaOU req now = do
  -- Step 1: Validate request
  validateUpgradeRequest req now

  -- Step 2: Build calldata
  calldata <- buildCompleteUpgradeCalldata req

  -- Step 3: Build execution params
  let execParams = MkUpgradeExecParams
        req.chainConfig
        (evmAddressHex req.proposal.ou)
        (evmAddressHex req.proposal.target)
        (evmAddressHex req.proposal.newImpl)
        (toSignatureBundle req.signatures)
        req.nonce
        req.maxGasPrice

  -- Step 4: Execute transaction
  result <- executeUpgrade execParams 300  -- 5 minute timeout

  -- Step 5: Interpret result
  case result.status of
    TxConfirmed block =>
      ok Update "executeUpgradeViaOU"
         ("Upgrade confirmed at block " ++ show block)
         (UpgradeSuccess result)
    TxFailed reason =>
      ok Update "executeUpgradeViaOU"
         ("Upgrade reverted: " ++ reason)
         (UpgradeReverted reason result)
    TxPending =>
      ok Update "executeUpgradeViaOU"
         "Upgrade timed out waiting for confirmation"
         (UpgradeTimeout result.txHash)

-- =============================================================================
-- Full Upgrade Orchestration
-- =============================================================================

||| Complete upgrade orchestration from approved proposal
||| Proposal must be in Approved state (checked at runtime)
public export
orchestrateUpgrade :
  Proposal ->         -- Must be in SApproved state
  VotingSession ->
  ChainTxConfig ->
  Nat ->              -- nonce
  Nat ->              -- maxGasPrice
  Nat ->              -- deadline
  Nat ->              -- currentTime
  FR UpgradeResult
orchestrateUpgrade proposal voting chainConfig nonce maxGasPrice deadline now = do
  -- Step 1: Check voting status
  votingResult <- checkVotingStatus voting now

  case votingResult of
    Left msg =>
      -- Voting not complete or expired
      ok Update "orchestrateUpgrade"
         ("Voting incomplete: " ++ msg)
         (UpgradeRejected msg)

    Right decision => case decision of
      ApproveUpgrade => do
        -- Step 2: Aggregate signatures
        sigs <- aggregateSignatures voting

        -- Step 3: Build request
        let req = MkUpgradeRequest
              proposal voting sigs chainConfig nonce maxGasPrice deadline

        -- Step 4: Execute
        executeUpgradeViaOU req now

      RejectUpgrade reason =>
        ok Update "orchestrateUpgrade"
           ("Proposal rejected: " ++ reason)
           (UpgradeRejected reason)

      RequestChanges changes =>
        ok Update "orchestrateUpgrade"
           ("Changes requested: " ++ changes)
           (UpgradeRejected ("Changes required: " ++ changes))

-- =============================================================================
-- Post-Execution Verification
-- =============================================================================

||| Verify upgrade was applied correctly on-chain
public export
verifyUpgradeApplied :
  ChainTxConfig ->
  String ->           -- proxy address
  String ->           -- expected implementation
  FR Bool
verifyUpgradeApplied config proxyAddr expectedImpl = do
  -- Would call proxy.implementation() and verify it matches expectedImpl
  -- This requires ethCall to be fully implemented
  fail Query "verifyUpgradeApplied"
       ("Verifying " ++ proxyAddr ++ " -> " ++ expectedImpl)
       (Internal "ethCall not fully implemented")

||| Record upgrade result in OUC state
public export
recordUpgradeResult :
  OUCState ->
  ProposalId ->
  UpgradeResult ->
  Nat ->              -- currentTime
  FR OUCState
recordUpgradeResult state pid result now =
  case result of
    UpgradeSuccess receipt =>
      markExecuted state pid receipt.txHash.hex now

    UpgradeReverted reason _ =>
      fail Update "recordUpgradeResult"
           ("Upgrade reverted: " ++ reason)
           (CallError reason)

    UpgradeTimeout txHash =>
      fail Update "recordUpgradeResult"
           ("Upgrade timed out: " ++ show txHash)
           (Timeout "Transaction confirmation timeout")

    UpgradeRejected reason =>
      fail Update "recordUpgradeResult"
           ("Upgrade rejected: " ++ reason)
           (Unauthorized reason)

    UpgradeFailed failure =>
      fail Update "recordUpgradeResult"
           ("Upgrade failed: " ++ show failure)
           failure

-- =============================================================================
-- Upgrade Lifecycle Summary
-- =============================================================================

||| Summary of upgrade lifecycle states
public export
data UpgradeLifecycleState
  = AwaitingVotes Nat Nat          -- (current votes, required votes)
  | AwaitingProposerSig
  | ReadyForExecution
  | ExecutionInProgress TxHash
  | ExecutionComplete TxHash Nat   -- (txHash, blockNumber)
  | ExecutionFailed String

public export
Show UpgradeLifecycleState where
  show (AwaitingVotes c r) = "AwaitingVotes(" ++ show c ++ "/" ++ show r ++ ")"
  show AwaitingProposerSig = "AwaitingProposerSig"
  show ReadyForExecution   = "ReadyForExecution"
  show (ExecutionInProgress h) = "ExecutionInProgress(" ++ show h ++ ")"
  show (ExecutionComplete h b) = "Complete(tx=" ++ show h ++ ", block=" ++ show b ++ ")"
  show (ExecutionFailed r) = "Failed: " ++ r

||| Get current lifecycle state from voting session
public export
getLifecycleState :
  VotingSession ->
  Maybe TxReceipt ->  -- Execution result if executed
  UpgradeLifecycleState
getLifecycleState voting execResult =
  case execResult of
    Just receipt => case receipt.status of
      TxConfirmed block => ExecutionComplete receipt.txHash block
      TxFailed reason   => ExecutionFailed reason
      TxPending         => ExecutionInProgress receipt.txHash
    Nothing =>
      if isNothing voting.proposerSig
        then AwaitingProposerSig
        else if isVotingComplete voting
          then ReadyForExecution
          else AwaitingVotes (length voting.votes) (length voting.requiredVoters)
