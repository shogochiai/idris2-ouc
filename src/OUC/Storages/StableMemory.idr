||| OUC Stable Memory Management
|||
||| Handles canister upgrade lifecycle:
||| - pre_upgrade: Serialize state to stable memory
||| - post_upgrade: Deserialize state from stable memory
||| - State versioning and migration
|||
||| ICP Canister Upgrade Flow:
|||   1. pre_upgrade() called → serialize heap to stable memory
|||   2. WASM module replaced
|||   3. post_upgrade() called → deserialize stable memory to heap
module OUC.Storages.StableMemory

import OUC.Functions.Core
import OUC.Storages.State
import Economics.Tier
import Data.List
import Data.String

%default total

-- =============================================================================
-- Subscription and Treasury Types (for serialization)
-- =============================================================================

||| Subscription info for stable storage
public export
record Subscription where
  constructor MkSubscription
  currentTier : Tier
  expiryDate  : Nat
  autoRenew   : Bool

||| Treasury balances for stable storage
public export
record Treasury where
  constructor MkTreasury
  ckEthBalance  : Nat
  icpBalance    : Nat
  cyclesBalance : Nat

-- =============================================================================
-- State Version (Migration Support)
-- =============================================================================

||| Current state schema version
||| Increment when adding breaking changes to state structure
public export
currentStateVersion : Nat
currentStateVersion = 2

||| State version history
||| v1: Initial (Auditors, Proposals)
||| v2: Added Economics (Subscription, Treasury, ProtocolAccounts)
public export
data StateVersion
  = V1  -- Initial schema
  | V2  -- Economics extension

public export
Show StateVersion where
  show V1 = "v1"
  show V2 = "v2"

public export
versionToNat : StateVersion -> Nat
versionToNat V1 = 1
versionToNat V2 = 2

public export
natToVersion : Nat -> Maybe StateVersion
natToVersion 1 = Just V1
natToVersion 2 = Just V2
natToVersion _ = Nothing

-- =============================================================================
-- Canister State
-- =============================================================================

||| Complete canister state for serialization
public export
record CanisterState where
  constructor MkCanisterState
  schemaVer     : Nat
  controller    : String            -- Controller principal
  -- Auditor Pool
  auditors      : List Auditor
  nextAuditorId : Nat
  -- Proposals
  proposals     : List UpgradeProposal
  nextProposalId: Nat
  -- Economics (v2)
  subscription  : Maybe Subscription
  treasury      : Maybe Treasury
  tier          : Tier

||| Initial empty state
public export
emptyCanisterState : String -> CanisterState
emptyCanisterState controller = MkCanisterState
  currentStateVersion
  controller
  []      -- auditors
  0       -- nextAuditorId
  []      -- proposals
  0       -- nextProposalId
  Nothing -- subscription
  Nothing -- treasury
  Archive -- default tier

-- =============================================================================
-- Serialization Format
-- =============================================================================

||| Field separator (cannot appear in data)
fieldSep : String
fieldSep = "\x00"

||| Record separator
recordSep : String
recordSep = "\x01"

||| Section separator
sectionSep : String
sectionSep = "\x02"

||| Serialize Tier to string code
tierToCode : Tier -> String
tierToCode Archive  = "0"
tierToCode Economy  = "1"
tierToCode Standard = "2"
tierToCode RealTime = "3"

||| Deserialize Tier from code
codeToTier : String -> Maybe Tier
codeToTier "0" = Just Archive
codeToTier "1" = Just Economy
codeToTier "2" = Just Standard
codeToTier "3" = Just RealTime
codeToTier _   = Nothing

||| Serialize Subscription
serializeSubscription : Subscription -> String
serializeSubscription (MkSubscription tier expiry renew) =
  tierToCode tier ++ fieldSep ++
  show expiry ++ fieldSep ++
  (if renew then "1" else "0")

||| Serialize Treasury
serializeTreasury : Treasury -> String
serializeTreasury t =
  show t.ckEthBalance ++ fieldSep ++
  show t.icpBalance ++ fieldSep ++
  show t.cyclesBalance

||| Serialize CanisterState header
serializeHeader : CanisterState -> String
serializeHeader (MkCanisterState ver ctrl _ audId _ propId _ _ tier) =
  show ver ++ fieldSep ++
  ctrl ++ fieldSep ++
  show audId ++ fieldSep ++
  show propId ++ fieldSep ++
  tierToCode tier

-- =============================================================================
-- Stable Memory FFI (5.3.2)
-- =============================================================================

||| FFI: Write bytes to stable memory
||| ic0.stable64_write(offset, src, size)
%foreign "C:ouc_stable_write,ouc_runtime"
prim__stableWrite : Int -> String -> Int -> PrimIO ()

||| FFI: Read bytes from stable memory
||| ic0.stable64_read(dst, offset, size)
%foreign "C:ouc_stable_read,ouc_runtime"
prim__stableRead : Int -> Int -> PrimIO String

||| FFI: Get stable memory size (in pages, 64KB each)
%foreign "C:ouc_stable_size,ouc_runtime"
prim__stableSize : PrimIO Int

||| FFI: Grow stable memory
%foreign "C:ouc_stable_grow,ouc_runtime"
prim__stableGrow : Int -> PrimIO Int

||| Write to stable memory
export
stableWrite : HasIO io => Int -> String -> io ()
stableWrite offset data_ = primIO $ prim__stableWrite offset data_ (cast (length data_))

||| Read from stable memory
export
stableRead : HasIO io => Int -> Int -> io String
stableRead offset size = primIO $ prim__stableRead offset size

||| Get stable memory size in bytes
export
stableSize : HasIO io => io Nat
stableSize = do
  pages <- primIO prim__stableSize
  pure (cast pages * 65536)  -- 64KB per page

||| Grow stable memory by n pages
export
stableGrow : HasIO io => Nat -> io Bool
stableGrow pages = do
  result <- primIO $ prim__stableGrow (cast pages)
  pure (result >= 0)

-- =============================================================================
-- Pre-upgrade / Post-upgrade Hooks
-- =============================================================================

||| Serialize state to stable memory (called by pre_upgrade)
export
serializeToStable : HasIO io => CanisterState -> io ()
serializeToStable state = do
  let header = serializeHeader state
  let auditorSection = concat (intersperse recordSep (map serializeAuditor state.auditors))
  let proposalSection = concat (intersperse recordSep (map serializeProposal state.proposals))
  let subscriptionSection = case state.subscription of
        Nothing => ""
        Just s => serializeSubscription s
  let treasurySection = case state.treasury of
        Nothing => ""
        Just t => serializeTreasury t
  let fullData = header ++ sectionSep ++
                 auditorSection ++ sectionSep ++
                 proposalSection ++ sectionSep ++
                 subscriptionSection ++ sectionSep ++
                 treasurySection
  -- Ensure enough stable memory
  let needed = length fullData
  currentSize <- stableSize
  when (needed > currentSize) $ do
    let pagesNeeded = (needed `divNat` 65536) + 1
    _ <- stableGrow pagesNeeded
    pure ()
  -- Write to stable memory
  stableWrite 0 fullData
  where
    divNat : Nat -> Nat -> Nat
    divNat n d = cast (cast {to=Integer} n `div` cast {to=Integer} d)

||| Deserialize state from stable memory (called by post_upgrade)
||| Returns Nothing if stable memory is empty or corrupted
export
deserializeFromStable : HasIO io => io (Maybe CanisterState)
deserializeFromStable = do
  size <- stableSize
  if size == 0
    then pure Nothing
    else do
      -- Read header first to get version
      rawData <- stableRead 0 (cast size)
      pure (parseCanisterState rawData)
  where
    parseCanisterState : String -> Maybe CanisterState
    parseCanisterState _ = Nothing  -- TODO: implement full parser

-- =============================================================================
-- Migration (5.3.2)
-- =============================================================================

||| Migrate state from old version to current
public export
migrateState : Nat -> CanisterState -> CanisterState
migrateState 1 old =
  -- V1 → V2: Add economics fields with defaults
  MkCanisterState
    2                   -- version
    old.controller
    old.auditors
    old.nextAuditorId
    old.proposals
    old.nextProposalId
    Nothing             -- subscription (new)
    Nothing             -- treasury (new)
    Archive             -- tier (new)
migrateState _ state = state  -- No migration needed

||| Check if migration is needed
public export
needsMigration : CanisterState -> Bool
needsMigration (MkCanisterState v _ _ _ _ _ _ _ _) = v < currentStateVersion

-- =============================================================================
-- Upgrade Hooks (Entry Points)
-- =============================================================================

||| Pre-upgrade hook
||| Called before WASM replacement to save state
export
preUpgrade : HasIO io => CanisterState -> io ()
preUpgrade = serializeToStable

||| Get version from canister state
getSchemaVer : CanisterState -> Nat
getSchemaVer (MkCanisterState v _ _ _ _ _ _ _ _) = v

||| Post-upgrade hook
||| Called after WASM replacement to restore state
export
postUpgrade : HasIO io => String -> io CanisterState
postUpgrade controller = do
  mState <- deserializeFromStable
  case mState of
    Nothing => pure (emptyCanisterState controller)
    Just cs =>
      if needsMigration cs
        then pure (migrateState (getSchemaVer cs) cs)
        else pure cs
