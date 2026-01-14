||| A-Life Economics - Tier System
|||
||| Service tier classification for Self-Amending Protocols.
||| Implements perpetual archive model with tier-based pricing.
|||
||| Tiers:
|||   Archive  - 1/day sync   (~¥3/month)
|||   Economy  - 1/hour sync  (~¥80/month)
|||   Standard - 1/15min sync (~¥300/month)
|||   RealTime - 1/min sync   (~¥4,500/month)
module Economics.Tier

import Data.Nat

%default total

-- Helper for safe division (returns 0 if divisor is 0)
safeDiv : Nat -> Nat -> Nat
safeDiv n m = case m of
  Z => 0
  S k => divNatNZ n (S k) ItIsSucc

-- =============================================================================
-- Tier Type
-- =============================================================================

||| Service tier for protocol monitoring
public export
data Tier
  = Archive    -- 1 sync/day   - Perpetual preservation
  | Economy    -- 1 sync/hour  - Low frequency updates
  | Standard   -- 1 sync/15min - General protocols
  | RealTime   -- 1 sync/min   - Active DeFi, DEX, MEV

public export
Show Tier where
  show Archive  = "Archive"
  show Economy  = "Economy"
  show Standard = "Standard"
  show RealTime = "RealTime"

public export
Eq Tier where
  Archive  == Archive  = True
  Economy  == Economy  = True
  Standard == Standard = True
  RealTime == RealTime = True
  _        == _        = False

||| Tier ordering (Archive < Economy < Standard < RealTime)
public export
Ord Tier where
  compare Archive  Archive  = EQ
  compare Archive  _        = LT
  compare Economy  Archive  = GT
  compare Economy  Economy  = EQ
  compare Economy  _        = LT
  compare Standard Archive  = GT
  compare Standard Economy  = GT
  compare Standard Standard = EQ
  compare Standard RealTime = LT
  compare RealTime RealTime = EQ
  compare RealTime _        = GT

-- =============================================================================
-- Tier Costs (in Cycles)
-- =============================================================================

||| Monthly cost in cycles for each tier
||| 1 trillion cycles ≈ ¥1,000 (rough estimate)
public export
tierMonthlyCost : Tier -> Nat
tierMonthlyCost Archive  = 3_000_000_000        -- ~¥3/month
tierMonthlyCost Economy  = 80_000_000_000       -- ~¥80/month
tierMonthlyCost Standard = 300_000_000_000      -- ~¥300/month
tierMonthlyCost RealTime = 4_500_000_000_000    -- ~¥4,500/month

||| Daily cost (monthly / 30)
public export
tierDailyCost : Tier -> Nat
tierDailyCost tier = safeDiv (tierMonthlyCost tier) 30

||| Sync interval in seconds
public export
tierSyncInterval : Tier -> Nat
tierSyncInterval Archive  = 86400   -- 1 day  = 86400 seconds
tierSyncInterval Economy  = 3600    -- 1 hour = 3600 seconds
tierSyncInterval Standard = 900     -- 15 min = 900 seconds
tierSyncInterval RealTime = 60      -- 1 min  = 60 seconds

||| Syncs per day
public export
tierSyncsPerDay : Tier -> Nat
tierSyncsPerDay Archive  = 1
tierSyncsPerDay Economy  = 24
tierSyncsPerDay Standard = 96    -- 24 * 4
tierSyncsPerDay RealTime = 1440  -- 24 * 60

-- =============================================================================
-- Tier Calculation
-- =============================================================================

||| Calculate affordable tier based on balance (for 30 days)
public export
calculateAffordableTier : Nat -> Tier
calculateAffordableTier balance =
  if balance >= tierMonthlyCost RealTime then RealTime
  else if balance >= tierMonthlyCost Standard then Standard
  else if balance >= tierMonthlyCost Economy then Economy
  else Archive

||| Calculate how many months a balance can sustain a tier
public export
calculateMonthsAtTier : Nat -> Tier -> Nat
calculateMonthsAtTier balance tier =
  let cost = tierMonthlyCost tier
  in safeDiv balance cost

||| Calculate how many years a balance can sustain Archive tier
||| (Used for perpetual archive messaging)
public export
calculateArchiveYears : Nat -> Nat
calculateArchiveYears balance =
  let months = calculateMonthsAtTier balance Archive
  in safeDiv months 12

-- =============================================================================
-- Tier Serialization
-- =============================================================================

||| Serialize tier to string
public export
serializeTier : Tier -> String
serializeTier Archive  = "0"
serializeTier Economy  = "1"
serializeTier Standard = "2"
serializeTier RealTime = "3"

||| Deserialize tier from string
public export
deserializeTier : String -> Maybe Tier
deserializeTier "0" = Just Archive
deserializeTier "1" = Just Economy
deserializeTier "2" = Just Standard
deserializeTier "3" = Just RealTime
deserializeTier _   = Nothing

-- =============================================================================
-- All Tiers (for iteration)
-- =============================================================================

||| List of all tiers in ascending order
public export
allTiers : List Tier
allTiers = [Archive, Economy, Standard, RealTime]

||| List of all tiers in descending order (for upgrade calculation)
public export
allTiersDesc : List Tier
allTiersDesc = [RealTime, Standard, Economy, Archive]
