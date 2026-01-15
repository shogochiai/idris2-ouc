||| OUC Candid Interface Types
|||
||| Defines types that map to can.did for Indexer integration.
||| These types are used for inter-canister call serialization.
module Candid.Interface

import Data.List
import Economics.Tier

%default total

-- =============================================================================
-- Indexer Query Response Types (5.3.1)
-- =============================================================================

||| Auditor info for Candid serialization
||| Maps to AuditorInfo in can.did
public export
record AuditorInfo where
  constructor MkAuditorInfo
  auditorId   : String
  principal   : String
  name        : String
  assignedOUs : List String
  status      : String
  reputation  : Nat

||| Subscription for Candid serialization
||| Maps to Subscription in can.did
public export
record SubscriptionInfo where
  constructor MkSubscriptionInfo
  currentTier : Tier
  expiryDate  : Nat
  autoRenew   : Bool

||| Treasury for Candid serialization
||| Maps to Treasury in can.did
public export
record TreasuryInfo where
  constructor MkTreasuryInfo
  ckEthBalance  : Nat
  icpBalance    : Nat
  cyclesBalance : Nat

-- =============================================================================
-- Show instances for JSON serialization
-- =============================================================================

export
Show AuditorInfo where
  show a = "{\"auditorId\":\"" ++ a.auditorId ++
           "\",\"principal\":\"" ++ a.principal ++
           "\",\"name\":\"" ++ a.name ++
           "\",\"assignedOUs\":" ++ showList a.assignedOUs ++
           ",\"status\":\"" ++ a.status ++
           "\",\"reputation\":" ++ show a.reputation ++ "}"
    where
      showList : List String -> String
      showList xs = "[" ++ concat (intersperse "," (map (\s => "\"" ++ s ++ "\"") xs)) ++ "]"

export
Show SubscriptionInfo where
  show s = "{\"currentTier\":\"" ++ show s.currentTier ++
           "\",\"expiryDate\":" ++ show s.expiryDate ++
           ",\"autoRenew\":" ++ (if s.autoRenew then "true" else "false") ++ "}"

export
Show TreasuryInfo where
  show t = "{\"ckEthBalance\":" ++ show t.ckEthBalance ++
           ",\"icpBalance\":" ++ show t.icpBalance ++
           ",\"cyclesBalance\":" ++ show t.cyclesBalance ++ "}"

-- =============================================================================
-- Service Method Types (Query/Update classification)
-- =============================================================================

||| Query method names (read-only, no state change)
public export
data QueryMethod
  = QGetAuditors
  | QGetSubscription
  | QGetTreasury
  | QGetProposal
  | QGetProposalsByChain
  | QGetProposalsByStatus

||| Update method names (state-changing)
public export
data UpdateMethod
  = USetTier
  | USetAutoRenew
  | URegisterOU
  | URegisterAuditor
  | UAssignOU

export
Show QueryMethod where
  show QGetAuditors = "getAuditors"
  show QGetSubscription = "getSubscription"
  show QGetTreasury = "getTreasury"
  show QGetProposal = "getProposal"
  show QGetProposalsByChain = "getProposalsByChain"
  show QGetProposalsByStatus = "getProposalsByStatus"

export
Show UpdateMethod where
  show USetTier = "setTier"
  show USetAutoRenew = "setAutoRenew"
  show URegisterOU = "registerOU"
  show URegisterAuditor = "registerAuditor"
  show UAssignOU = "assignOU"

-- =============================================================================
-- Conversion utilities
-- =============================================================================

||| Convert internal Tier to Candid representation
public export
tierToCandid : Tier -> String
tierToCandid Archive  = "Archive"
tierToCandid Economy  = "Economy"
tierToCandid Standard = "Standard"
tierToCandid RealTime = "RealTime"

||| Parse Candid Tier variant
public export
candidToTier : String -> Maybe Tier
candidToTier "Archive"  = Just Archive
candidToTier "Economy"  = Just Economy
candidToTier "Standard" = Just Standard
candidToTier "RealTime" = Just RealTime
candidToTier _ = Nothing
