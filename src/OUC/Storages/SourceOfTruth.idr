||| Source of Truth Classification
|||
||| Type-level encoding of data ownership in System of Systems.
||| Prevents confusion about where data lives and who owns it.
|||
||| Key principle: "Reference, Don't Copy"
||| - IC-owned data: stored directly
||| - EVM-owned data: store hash/reference only
||| - Cached data: can be rebuilt from source
module OUC.Storages.SourceOfTruth

%default total

-- =============================================================================
-- Data Ownership
-- =============================================================================

||| Chain identifier for EVM
public export
SoTChainId : Type
SoTChainId = Nat

||| Who owns the canonical version of this data?
public export
data Owner
  = IC              -- IC Canister is source of truth
  | EVM SoTChainId  -- EVM chain is source of truth
  | Blob            -- External blob storage (IPFS, etc.)

public export
Show Owner where
  show IC = "IC"
  show (EVM c) = "EVM(" ++ show c ++ ")"
  show Blob = "Blob"

-- =============================================================================
-- Storage Strategy
-- =============================================================================

||| How data is stored based on ownership
public export
data StorageStrategy : (owner : Owner) -> Type -> Type where
  ||| Full data stored (IC is source of truth)
  Own : a -> StorageStrategy IC a

  ||| Reference only (external source of truth)
  ||| Contains hash for verification
  Ref : (hash : String) -> StorageStrategy owner a

  ||| Cached copy with expiry (can be rebuilt)
  Cache : a -> (hash : String) -> (expiry : Nat) -> StorageStrategy owner a

||| Extract value (if available)
public export
getValue : StorageStrategy owner a -> Maybe a
getValue (Own x) = Just x
getValue (Ref _) = Nothing
getValue (Cache x _ _) = Just x

||| Extract hash (for verification)
public export
getHash : StorageStrategy owner a -> Maybe String
getHash (Own _) = Nothing
getHash (Ref h) = Just h
getHash (Cache _ h _) = Just h

-- =============================================================================
-- Data Lifecycle
-- =============================================================================

||| Data lifecycle classification
public export
data Lifecycle
  = Immutable    -- Never delete (audit trail)
  | Archivable   -- Can move to cold storage after N days
  | Ephemeral    -- Can delete after use
  | Derived      -- Can regenerate from source

public export
Show Lifecycle where
  show Immutable = "IMMUTABLE"
  show Archivable = "ARCHIVABLE"
  show Ephemeral = "EPHEMERAL"
  show Derived = "DERIVED"

-- =============================================================================
-- OUC Data Classification
-- =============================================================================

||| Proposal data ownership
||| - Proposal metadata: IC owns
||| - Code implementation: EVM owns (we store hash)
public export
record ProposalData where
  constructor MkProposalData
  -- IC-owned (stored directly)
  proposalId    : Nat
  status        : String
  createdAt     : Nat
  -- EVM-owned (reference only)
  targetHash    : String    -- Hash of target contract
  implCodeHash  : String    -- Hash of new implementation
  chainId       : Nat

||| Auditor data ownership
||| All IC-owned
public export
record AuditorData where
  constructor MkAuditorData
  principal     : String
  reputation    : Nat
  stakedAmount  : Nat
  registeredAt  : Nat

||| Event data from EVM (cached, rebuildable)
public export
record CachedEvent where
  constructor MkCachedEvent
  -- Event content (EVM is truth, this is cache)
  chainId       : Nat
  blockNum      : Nat
  logIndex      : Nat
  topics        : List String
  data_         : String
  -- IC-owned metadata
  observedAt    : Nat       -- When IC saw it
  syncCursor    : Nat       -- Sync progress
  interpretation: Maybe String  -- Our interpretation

-- =============================================================================
-- Type-Safe Data Access
-- =============================================================================

||| Proof that data is IC-owned (safe to modify)
public export
data ICOwned : Type -> Type where
  MkICOwned : a -> ICOwned a

||| Proof that data is cached (safe to invalidate)
public export
data Cached : Type -> Type where
  MkCached : a -> (rebuildFrom : String) -> Cached a

||| Proof that data is a reference (cannot modify content)
public export
data RefOnly : Type -> Type where
  MkRefOnly : (hash : String) -> RefOnly a

-- =============================================================================
-- Data Classification Table (as types)
-- =============================================================================

||| Classification for OUC data types
public export
interface DataClassification a where
  owner : Owner
  lifecycle : Lifecycle

public export
DataClassification ProposalData where
  owner = IC
  lifecycle = Immutable

public export
DataClassification AuditorData where
  owner = IC
  lifecycle = Archivable

public export
DataClassification CachedEvent where
  owner = EVM 1  -- Default to chain 1
  lifecycle = Derived
