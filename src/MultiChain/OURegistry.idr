||| OU Registry
|||
||| Manages registered OUs across multiple chains.
||| OUC tracks OU locations and states for Dashboard and Tx relay.
module MultiChain.OURegistry

import MultiChain.Registry
import Data.List

%default total

-- =============================================================================
-- Registered OU
-- =============================================================================

||| Registered OU on a specific chain
public export
record RegisteredOU where
  constructor MkRegisteredOU
  ouId            : Nat
  chainId         : ChainId
  ouAddress       : EvmAddress       -- OU contract address
  dictionaryAddr  : EvmAddress       -- Shared Dictionary
  registeredAt    : Nat
  lastSyncAt      : Nat              -- Last state sync
  isActive        : Bool

public export
Show RegisteredOU where
  show ou = "OU#" ++ show ou.ouId ++ " on " ++ show ou.chainId

public export
Eq RegisteredOU where
  ou1 == ou2 = ou1.ouId == ou2.ouId && ou1.chainId == ou2.chainId

-- =============================================================================
-- OU State Snapshot
-- =============================================================================

||| OU state snapshot (from chain query via HTTP Outcall)
public export
record OUStateSnapshot where
  constructor MkOUStateSnapshot
  ouId            : Nat
  proposalCount   : Nat
  pendingCount    : Nat              -- Proposals awaiting audit
  approvedCount   : Nat
  rejectedCount   : Nat
  auditorCount    : Nat
  queriedAt       : Nat              -- Timestamp
  blockNumber     : Nat              -- Block at query time

public export
Show OUStateSnapshot where
  show s = "OU#" ++ show s.ouId ++
           " proposals=" ++ show s.proposalCount ++
           " pending=" ++ show s.pendingCount

-- =============================================================================
-- OU Registry State
-- =============================================================================

||| OU Registry maintains all known OUs
public export
record OURegistryState where
  constructor MkOURegistryState
  ous             : List RegisteredOU
  snapshots       : List OUStateSnapshot  -- Latest snapshots
  nextOuId        : Nat
  lastUpdated     : Nat

public export
emptyOURegistry : OURegistryState
emptyOURegistry = MkOURegistryState [] [] 0 0

-- =============================================================================
-- Registry Operations
-- =============================================================================

||| Register new OU
public export
registerOU :
  OURegistryState ->
  ChainId ->
  EvmAddress ->      -- OU address
  EvmAddress ->      -- Dictionary address
  Nat ->             -- Current time
  (OURegistryState, Nat)  -- Updated state + assigned ouId
registerOU state chainId ouAddr dictAddr now =
  let ouId = state.nextOuId
      newOU = MkRegisteredOU ouId chainId ouAddr dictAddr now now True
      updated = { ous := newOU :: state.ous
                , nextOuId := ouId + 1
                , lastUpdated := now
                } state
  in (updated, ouId)

||| Find OU by ID
public export
findOU : OURegistryState -> Nat -> Maybe RegisteredOU
findOU state ouId = find (\ou => ou.ouId == ouId) state.ous

||| Find OUs by chain
public export
findOUsByChain : OURegistryState -> ChainId -> List RegisteredOU
findOUsByChain state chainId = filter (\ou => ou.chainId == chainId) state.ous

||| Get all active OUs
public export
getActiveOUs : OURegistryState -> List RegisteredOU
getActiveOUs state = filter (.isActive) state.ous

||| Update OU state snapshot
public export
updateSnapshot : OURegistryState -> OUStateSnapshot -> Nat -> OURegistryState
updateSnapshot state snapshot now =
  let filtered = filter (\s => s.ouId /= snapshot.ouId) state.snapshots
  in { snapshots := snapshot :: filtered, lastUpdated := now } state

||| Get latest snapshot for OU
public export
getSnapshot : OURegistryState -> Nat -> Maybe OUStateSnapshot
getSnapshot state ouId = find (\s => s.ouId == ouId) state.snapshots

||| Deactivate OU
public export
deactivateOU : OURegistryState -> Nat -> Nat -> OURegistryState
deactivateOU state ouId now =
  let deactivate : RegisteredOU -> RegisteredOU
      deactivate ou = if ou.ouId == ouId then { isActive := False } ou else ou
      updated = map deactivate state.ous
  in { ous := updated, lastUpdated := now } state

||| Reactivate OU
public export
reactivateOU : OURegistryState -> Nat -> Nat -> OURegistryState
reactivateOU state ouId now =
  let reactivate : RegisteredOU -> RegisteredOU
      reactivate ou = if ou.ouId == ouId then { isActive := True } ou else ou
      updated = map reactivate state.ous
  in { ous := updated, lastUpdated := now } state

||| Get OU count
public export
getOUCount : OURegistryState -> Nat
getOUCount state = length state.ous

||| Get active OU count
public export
getActiveOUCount : OURegistryState -> Nat
getActiveOUCount state = length (getActiveOUs state)

-- =============================================================================
-- Aggregated Stats (for Dashboard)
-- =============================================================================

||| Aggregated stats across all OUs
public export
record AggregatedOUStats where
  constructor MkAggregatedOUStats
  totalOUs        : Nat
  activeOUs       : Nat
  totalProposals  : Nat
  totalPending    : Nat
  totalApproved   : Nat
  totalRejected   : Nat
  calculatedAt    : Nat

||| Calculate aggregated stats from snapshots
public export
aggregateStats : OURegistryState -> Nat -> AggregatedOUStats
aggregateStats state now =
  let proposals = sum (map (.proposalCount) state.snapshots)
      pending = sum (map (.pendingCount) state.snapshots)
      approved = sum (map (.approvedCount) state.snapshots)
      rejected = sum (map (.rejectedCount) state.snapshots)
  in MkAggregatedOUStats
       (getOUCount state)
       (getActiveOUCount state)
       proposals
       pending
       approved
       rejected
       now
  where
    sum : List Nat -> Nat
    sum = foldr (+) 0
