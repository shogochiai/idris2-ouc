||| Failure-Aware Build Infrastructure Core Types
|||
||| FR Monads に基づくビルドサーバー仕様の型定義
module FABI.Core

import Data.List

-- =============================================================================
-- HASH TYPES
-- =============================================================================

||| 256-bit hash represented as hex string (64 chars)
public export
Hash256 : Type
Hash256 = String

||| Validate hash format (0x + 64 hex chars)
public export
isValidHash : Hash256 -> Bool
isValidHash h =
  length h == 66 &&
  take 2 h == "0x"

-- =============================================================================
-- BUILD ENVIRONMENT
-- =============================================================================

||| Tool version specification
public export
record ToolVersion where
  constructor MkToolVersion
  name : String      -- "idris2", "pack", "emcc", etc.
  version : String   -- "0.7.0", "0.1.0", etc.
  hash : Hash256     -- Binary hash for verification

||| System dependency specification
public export
record SystemDep where
  constructor MkSystemDep
  package : String   -- "gmp", "zlib", etc.
  version : String   -- "6.3.0", "1.3.1", etc.

||| Container specification
public export
data ContainerType = Docker | Nix | Bazel

export
Show ContainerType where
  show Docker = "docker"
  show Nix = "nix"
  show Bazel = "bazel"

||| Full build environment definition
public export
record BuildEnv where
  constructor MkBuildEnv
  containerType : ContainerType
  containerHash : Hash256
  baseImage : String
  tools : List ToolVersion
  systemDeps : List SystemDep
  hermetic : Bool    -- True if --network=none enforced

-- =============================================================================
-- HASH SCHEMA
-- =============================================================================

||| Source code hash (all .idr, .c, pack.toml)
public export
record SourceHash where
  constructor MkSourceHash
  hash : Hash256
  fileCount : Nat
  totalBytes : Nat

||| Lockfile hash (pack.lock with all transitive deps)
public export
record LockfileHash where
  constructor MkLockfileHash
  hash : Hash256
  depCount : Nat

||| Environment hash (env.toml + container derivation)
public export
record EnvHash where
  constructor MkEnvHash
  hash : Hash256
  containerType : ContainerType

||| Composed build input hash
public export
record InputHash where
  constructor MkInputHash
  sourceHash : SourceHash
  lockfileHash : LockfileHash
  envHash : EnvHash
  composedHash : Hash256  -- hash(source || lock || env)

||| Build output hash (wasm, did, metadata)
public export
record OutputHash where
  constructor MkOutputHash
  wasmHash : Hash256
  didHash : Hash256
  metadataHash : Hash256
  composedHash : Hash256

-- =============================================================================
-- BUILD EVIDENCE
-- =============================================================================

||| Builder identity
public export
record BuilderId where
  constructor MkBuilderId
  pubkey : String    -- Public key (hex encoded)
  name : String      -- Human-readable name
  baseImage : String -- Alpine, Debian, Nix, etc.

||| Signature over build evidence
public export
record BuildSignature where
  constructor MkBuildSignature
  builderId : BuilderId
  signature : String -- Ed25519 signature (hex)
  algorithm : String -- "ed25519"

||| Complete build evidence
public export
record BuildEvidence where
  constructor MkBuildEvidence
  inputHash : InputHash
  outputHash : OutputHash
  timestamp : Nat           -- Unix timestamp
  signature : BuildSignature
  previousHash : Maybe Hash256  -- Chain to prior evidence
  logsHash : Hash256        -- Build logs hash for retrieval

||| Build evidence chain (for verification)
public export
record EvidenceChain where
  constructor MkEvidenceChain
  genesis : BuildEvidence
  chain : List BuildEvidence
  head : BuildEvidence

-- =============================================================================
-- N-OF-N BUILDER NETWORK
-- =============================================================================

||| Builder registration
public export
record RegisteredBuilder where
  constructor MkRegisteredBuilder
  builderId : BuilderId
  stake : Nat           -- Staked amount
  registeredAt : Nat    -- Unix timestamp
  isActive : Bool

||| Build result from a single builder
public export
record BuildResult where
  constructor MkBuildResult
  builderId : BuilderId
  outputHash : OutputHash
  evidence : BuildEvidence
  submittedAt : Nat

||| Build consensus state
public export
data BuildConsensus
  = Pending (List BuildResult)     -- Waiting for all builders
  | Agreed Hash256                 -- n-of-n agreement on outputHash
  | Disputed (List BuildResult)    -- Hash mismatch detected

-- =============================================================================
-- DISPUTE HANDLING
-- =============================================================================

||| Dispute record
public export
record BuildDispute where
  constructor MkBuildDispute
  disputeId : Nat
  inputHash : InputHash
  builderClaims : List BuildResult
  createdAt : Nat
  investigationDeadline : Nat

||| Dispute resolution
public export
data DisputeResolution
  = IdentifiedMalicious BuilderId Nat   -- Builder, slash amount
  | EnvironmentContamination            -- f_env, all rebuild
  | Inconclusive                        -- No fault determined

-- =============================================================================
-- BUILDER REPLACEMENT
-- =============================================================================

||| Replacement request
public export
record ReplacementRequest where
  constructor MkReplacementRequest
  oldBuilder : BuilderId
  newBuilder : BuilderId
  reason : String
  approvals : List String  -- Auditor signatures
  requestedAt : Nat

||| Replacement status
public export
data ReplacementStatus
  = ReplacementPending
  | ReplacementApproved
  | ReplacementCapabilityProving  -- New builder proving capability
  | ReplacementComplete
  | ReplacementRejected String

-- =============================================================================
-- ENVIRONMENT MIGRATION
-- =============================================================================

||| Migration request
public export
record MigrationRequest where
  constructor MkMigrationRequest
  oldEnv : BuildEnv
  newEnv : BuildEnv
  backwardCompatVerified : Bool
  migrationEvidence : Maybe BuildEvidence

||| Migration status
public export
data MigrationStatus
  = MigrationPending
  | MigrationInProgress
  | MigrationComplete
  | MigrationRolledBack String

-- =============================================================================
-- EMERGENCY REBUILD
-- =============================================================================

||| Emergency build request
public export
record EmergencyBuildRequest where
  constructor MkEmergencyBuildRequest
  reason : String
  requestedBy : String     -- Auditor or governance
  auditorApprovals : List String
  requestedAt : Nat

||| Provisional build (emergency)
public export
record ProvisionalBuild where
  constructor MkProvisionalBuild
  evidence : BuildEvidence
  provisionalUntil : Nat   -- emergencyTimeout deadline
  confirmedBy : List BuilderId  -- Builders that confirmed

-- =============================================================================
-- FAILURE SINK DIAGNOSTICS
-- =============================================================================

||| Build failure classification (from FABI.md Section 2.3)
public export
data BuildFailure
  = F_Env String    -- Environment contamination
  | F_Key String    -- Key leak/loss
  | F_Repro String  -- Non-reproducible build
  | F_Ops String    -- Operator liveness failure

||| Rebinding action recommendation
public export
data RebindingAction
  = RebuildInFreshEnv
  | RotateBuilderKeys
  | RequestIndependentBuild
  | InvokeEmergencyPath
  | EscalateToGovernance String

||| Diagnostic result
public export
record DiagnosticResult where
  constructor MkDiagnosticResult
  failure : BuildFailure
  severity : Nat        -- 0-10 scale
  rebindingAction : RebindingAction
  evidence : String     -- Supporting evidence

-- =============================================================================
-- OUC INTEGRATION TYPES
-- =============================================================================

||| Build evidence attachment for OUC proposal
public export
record ProposalBuildAttachment where
  constructor MkProposalBuildAttachment
  evidenceHash : Hash256
  sourceHash : Hash256
  outputWasmHash : Hash256
  builderCount : Nat
  consensusType : BuildConsensus

||| Auditor verification of build
public export
record AuditorBuildVerification where
  constructor MkAuditorBuildVerification
  auditorId : String
  proposalId : Nat
  rebuildRequested : Bool
  rebuildResult : Maybe BuildResult
  verified : Bool
  verifiedAt : Nat

-- =============================================================================
-- CONFIGURATION CONSTANTS
-- =============================================================================

||| Minimum builder stake (in protocol tokens)
public export
minBuilderStake : Nat
minBuilderStake = 10000

||| Minimum number of active builders
public export
minBuilderCount : Nat
minBuilderCount = 3

||| Investigation period for disputes (seconds)
public export
minInvestigationPeriod : Nat
minInvestigationPeriod = 604800  -- 7 days

||| Transition period for builder replacement (seconds)
public export
transitionPeriod : Nat
transitionPeriod = 2592000  -- 30 days

||| Emergency timeout for provisional builds (seconds)
public export
emergencyTimeout : Nat
emergencyTimeout = 86400  -- 24 hours

||| Verification timeout for auditor builds (seconds)
public export
verificationTimeout : Nat
verificationTimeout = 172800  -- 48 hours
