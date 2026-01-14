||| Auditor Signature Relay
|||
||| Collects Auditor EVM signatures and relays to OU via Threshold ECDSA.
||| Pattern: Auditor signs message → OUC collects → threshold check → Tx relay
module MultiChain.AuditorRelay

import MultiChain.Registry
import MultiChain.OURegistry
import Data.List

%default total

-- =============================================================================
-- Auditor Signature
-- =============================================================================

||| EVM signature (65 bytes: r[32] + s[32] + v[1])
public export
record EvmSignature where
  constructor MkEvmSignature
  r : String         -- 32 bytes hex
  s : String         -- 32 bytes hex
  v : Nat            -- Recovery id (27 or 28)

public export
Show EvmSignature where
  show sig = "0x" ++ sig.r ++ sig.s ++ show sig.v

||| Signed audit approval from an Auditor
public export
record AuditorApproval where
  constructor MkAuditorApproval
  auditorAddr     : EvmAddress       -- Auditor's EVM address
  ouId            : Nat
  proposalId      : Nat
  approve         : Bool             -- True = approve, False = reject
  signature       : EvmSignature     -- EIP-712 typed data signature
  submittedAt     : Nat

public export
Show AuditorApproval where
  show a = "Approval(" ++ show a.auditorAddr ++
           ", OU#" ++ show a.ouId ++
           ", proposal=" ++ show a.proposalId ++
           ", " ++ (if a.approve then "APPROVE" else "REJECT") ++ ")"

-- =============================================================================
-- Signature Collection State
-- =============================================================================

||| Pending approval collection for a specific proposal
public export
record PendingApprovalCollection where
  constructor MkPendingApprovalCollection
  ouId            : Nat
  proposalId      : Nat
  chainId         : ChainId
  ouAddress       : EvmAddress
  requiredCount   : Nat              -- Threshold (n-of-m)
  approvals       : List AuditorApproval
  rejections      : List AuditorApproval
  createdAt       : Nat
  expiresAt       : Nat              -- Collection deadline

||| Check if threshold is reached for approvals
public export
isApprovalThresholdMet : PendingApprovalCollection -> Bool
isApprovalThresholdMet collection =
  length collection.approvals >= collection.requiredCount

||| Check if threshold is reached for rejections
public export
isRejectionThresholdMet : PendingApprovalCollection -> Bool
isRejectionThresholdMet collection =
  length collection.rejections >= collection.requiredCount

||| Check if collection is expired
public export
isExpired : PendingApprovalCollection -> Nat -> Bool
isExpired collection now = now > collection.expiresAt

-- =============================================================================
-- Relay State
-- =============================================================================

||| Relay result
public export
data RelayResult
  = RelayApproved Nat    -- Approval count
  | RelayRejected Nat    -- Rejection count
  | RelayExpired
  | RelayFailed String   -- Error message

public export
Show RelayResult where
  show (RelayApproved n) = "APPROVED(" ++ show n ++ ")"
  show (RelayRejected n) = "REJECTED(" ++ show n ++ ")"
  show RelayExpired = "EXPIRED"
  show (RelayFailed msg) = "FAILED: " ++ msg

||| Completed relay record
public export
record CompletedRelay where
  constructor MkCompletedRelay
  ouId            : Nat
  proposalId      : Nat
  result          : RelayResult
  txHash          : Maybe String     -- EVM tx hash if sent
  completedAt     : Nat

||| Auditor Relay state
public export
record AuditorRelayState where
  constructor MkAuditorRelayState
  pendingCollections : List PendingApprovalCollection
  completedRelays    : List CompletedRelay
  registeredAuditors : List EvmAddress  -- Known Auditor addresses
  defaultThreshold   : Nat              -- Default n-of-m threshold
  collectionTimeout  : Nat              -- Seconds until expiry

-- =============================================================================
-- Relay Operations
-- =============================================================================

||| Initial relay state
public export
emptyRelayState : AuditorRelayState
emptyRelayState = MkAuditorRelayState [] [] [] 2 86400  -- 2-of-n, 24h timeout

||| Start new approval collection
public export
startCollection :
  AuditorRelayState ->
  Nat ->             -- ouId
  Nat ->             -- proposalId
  ChainId ->
  EvmAddress ->      -- OU address
  Nat ->             -- Current time
  AuditorRelayState
startCollection state ouId proposalId chainId ouAddr now =
  let collection = MkPendingApprovalCollection
        ouId proposalId chainId ouAddr
        state.defaultThreshold
        [] []
        now
        (now + state.collectionTimeout)
  in { pendingCollections := collection :: state.pendingCollections } state

||| Find pending collection
public export
findCollection :
  AuditorRelayState ->
  Nat ->             -- ouId
  Nat ->             -- proposalId
  Maybe PendingApprovalCollection
findCollection state ouId proposalId =
  find (\c => c.ouId == ouId && c.proposalId == proposalId) state.pendingCollections

||| Submit auditor approval
public export
submitApproval :
  AuditorRelayState ->
  AuditorApproval ->
  Either String AuditorRelayState
submitApproval state approval =
  -- Check if auditor is registered
  if not (elem approval.auditorAddr state.registeredAuditors)
  then Left "Auditor not registered"
  else case findCollection state approval.ouId approval.proposalId of
    Nothing => Left "No pending collection for this proposal"
    Just collection =>
      -- Check for duplicate
      let existingAddrs = map (.auditorAddr) (collection.approvals ++ collection.rejections)
      in if elem approval.auditorAddr existingAddrs
         then Left "Auditor already submitted"
         else
           let updatedCollection =
                 if approval.approve
                 then { approvals := approval :: collection.approvals } collection
                 else { rejections := approval :: collection.rejections } collection
               updatedCollections = map (\c =>
                 if c.ouId == approval.ouId && c.proposalId == approval.proposalId
                 then updatedCollection
                 else c) state.pendingCollections
           in Right ({ pendingCollections := updatedCollections } state)

||| Register auditor address
public export
registerAuditor : AuditorRelayState -> EvmAddress -> AuditorRelayState
registerAuditor state addr =
  if elem addr state.registeredAuditors
  then state
  else { registeredAuditors := addr :: state.registeredAuditors } state

||| Unregister auditor address
public export
unregisterAuditor : AuditorRelayState -> EvmAddress -> AuditorRelayState
unregisterAuditor state addr =
  { registeredAuditors := filter (/= addr) state.registeredAuditors } state

-- =============================================================================
-- Threshold Check & Relay Trigger
-- =============================================================================

||| Check collection status
public export
data CollectionStatus
  = CollectionPending Nat Nat   -- approvals, rejections so far
  | CollectionReadyApprove      -- Threshold met for approval
  | CollectionReadyReject       -- Threshold met for rejection
  | CollectionExpired

public export
Show CollectionStatus where
  show (CollectionPending a r) = "PENDING(approve=" ++ show a ++ ", reject=" ++ show r ++ ")"
  show CollectionReadyApprove = "READY_APPROVE"
  show CollectionReadyReject = "READY_REJECT"
  show CollectionExpired = "EXPIRED"

||| Get collection status
public export
getCollectionStatus : PendingApprovalCollection -> Nat -> CollectionStatus
getCollectionStatus collection now =
  if isExpired collection now
  then CollectionExpired
  else if isApprovalThresholdMet collection
       then CollectionReadyApprove
       else if isRejectionThresholdMet collection
            then CollectionReadyReject
            else CollectionPending
                   (length collection.approvals)
                   (length collection.rejections)

-- =============================================================================
-- Message Hash for EIP-712 Signing
-- =============================================================================

||| Build message to be signed by Auditor
||| Auditor signs: keccak256(abi.encode(proposalId, approve, chainId, ouAddr))
public export
buildSignMessage : Nat -> Bool -> ChainId -> EvmAddress -> String
buildSignMessage proposalId approve chainId ouAddr =
  -- This would be actual keccak256 in production
  -- For now, return a placeholder format
  "SIGN:" ++ show proposalId ++
  ":" ++ (if approve then "1" else "0") ++
  ":" ++ show chainId ++
  ":" ++ show ouAddr

-- =============================================================================
-- Relay Calldata Builder
-- =============================================================================

||| Build calldata for OU.submitAuditResult(proposalId, signatures[])
public export
record RelayCalldata where
  constructor MkRelayCalldata
  selector        : String           -- Function selector (4 bytes)
  proposalId      : Nat
  signatures      : List EvmSignature
  encodedLength   : Nat              -- Total calldata length

||| Build relay calldata
public export
buildRelayCalldata : PendingApprovalCollection -> RelayCalldata
buildRelayCalldata collection =
  let sigs = map (.signature) collection.approvals
      -- submitAuditResult(uint256,bytes[]) selector
      selector = "0x12345678"  -- Placeholder, compute actual selector
  in MkRelayCalldata selector collection.proposalId sigs (4 + 32 + length sigs * 65)
