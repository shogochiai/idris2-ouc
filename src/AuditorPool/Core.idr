||| AuditorPool Module
|||
||| Manages the pool of auditors who can review upgrade proposals.
||| Implements:
||| - Auditor registration and staking
||| - Reputation tracking
||| - Selection algorithms
||| - Slashing for misbehavior
module AuditorPool.Core

import FRC.Core
import OUC.Core
import Data.List

%default total

-- =============================================================================
-- Auditor Pool State
-- =============================================================================

||| Minimum stake required to become an auditor
public export
minStake : Nat
minStake = 1000  -- In base token units

||| Reputation threshold for selection
public export
minReputation : Nat
minReputation = 500  -- Out of 1000

||| Configuration for auditor pool
public export
record PoolConfig where
  constructor MkPoolConfig
  minStakeAmount    : Nat
  minReputationScore: Nat
  maxActiveAuditors : Nat
  slashPercentage   : Nat   -- Percentage of stake to slash (0-100)

||| Default pool configuration
public export
defaultConfig : PoolConfig
defaultConfig = MkPoolConfig minStake minReputation 100 10

-- =============================================================================
-- Auditor Selection
-- =============================================================================

||| Selection criteria for auditor assignment
public export
data SelectionCriteria
  = ByReputation         -- Highest reputation first
  | ByAvailability       -- Least loaded auditors
  | Random Nat           -- Randomized selection (seed)
  | Weighted             -- Weighted by stake * reputation

public export
Show SelectionCriteria where
  show ByReputation   = "ByReputation"
  show ByAvailability = "ByAvailability"
  show (Random s)     = "Random(" ++ show s ++ ")"
  show Weighted       = "Weighted"

-- =============================================================================
-- Pool Operations (FRC-compliant)
-- =============================================================================

||| Register a new auditor
public export
registerAuditor :
  List Auditor ->
  Principal ->
  Nat ->               -- stake amount
  Nat ->               -- currentTime
  PoolConfig ->
  FR (List Auditor, AuditorId)
registerAuditor auditors principal stakeAmount now config =
  if stakeAmount < config.minStakeAmount
    then fail Update "registerAuditor" "Insufficient stake"
              (Unauthorized ("Stake " ++ show stakeAmount ++ " < " ++ show config.minStakeAmount))
    else
      let aid = MkAuditorId (MkPrincipal principal.text)
          existing = find (\a => a.id == aid) auditors
      in case existing of
        Just _ => fail Update "registerAuditor" "Already registered"
                       (Conflict "Auditor already exists")
        Nothing =>
          let auditor = MkAuditor aid Active 500 0 0 0 0 stakeAmount now
          in ok Update "registerAuditor" ("Registered " ++ show aid)
               (auditor :: auditors, aid)

||| Get active auditors meeting criteria
public export
getActiveAuditors : List Auditor -> PoolConfig -> List Auditor
getActiveAuditors auditors config =
  filter (\a => a.status == Active && a.reputation >= config.minReputationScore) auditors

||| Select auditor for proposal assignment
public export
selectAuditor :
  List Auditor ->
  SelectionCriteria ->
  PoolConfig ->
  FR AuditorId
selectAuditor auditors criteria config =
  let active = getActiveAuditors auditors config
  in case active of
    [] => fail Query "selectAuditor" "No auditors available"
               (NotFound "No active auditors meeting criteria")
    (a :: rest) => case criteria of
      ByReputation =>
        let sorted = sortBy (\x, y => compare y.reputation x.reputation) active
        in case sorted of
          [] => fail Query "selectAuditor" "No auditors" (Internal "Sort failed")
          (best :: _) => ok Query "selectAuditor" ("Selected " ++ show best.id) best.id
      ByAvailability =>
        let sorted = sortBy (\x, y => compare x.totalReviews y.totalReviews) active
        in case sorted of
          [] => fail Query "selectAuditor" "No auditors" (Internal "Sort failed")
          (best :: _) => ok Query "selectAuditor" ("Selected " ++ show best.id) best.id
      Random seed =>
        let idx = mod seed (length active)
        in case index' idx active of
          Just selected => ok Query "selectAuditor" ("Selected " ++ show selected.id) selected.id
          Nothing => ok Query "selectAuditor" ("Selected " ++ show a.id) a.id
      Weighted =>
        -- Simplified: just use highest weighted score
        let weighted = map (\a => (a, a.reputation * a.stakedAmount)) active
            sorted = sortBy (\(_, w1), (_, w2) => compare w2 w1) weighted
        in case sorted of
          [] => fail Query "selectAuditor" "No auditors" (Internal "Weighted sort failed")
          ((best, _) :: _) => ok Query "selectAuditor" ("Selected " ++ show best.id) best.id

||| Update auditor reputation after review
public export
updateReputation :
  List Auditor ->
  AuditorId ->
  Int ->               -- reputation delta (can be negative)
  FR (List Auditor)
updateReputation auditors aid delta =
  let found = find (\a => a.id == aid) auditors
  in case found of
    Nothing => notFound Update "updateReputation" ("Auditor " ++ show aid ++ " not found")
    Just auditor =>
      let newRep = if delta >= 0
            then min 1000 (auditor.reputation + cast delta)
            else let d = cast (abs delta) in
                 if d > auditor.reputation then 0 else auditor.reputation `minus` d
          updated = { reputation := newRep } auditor
          newList = map (\a => if a.id == aid then updated else a) auditors
      in ok Update "updateReputation"
            ("Updated " ++ show aid ++ " reputation to " ++ show newRep)
            newList

||| Slash auditor for misbehavior
public export
slashAuditor :
  List Auditor ->
  AuditorId ->
  String ->            -- reason
  PoolConfig ->
  FR (List Auditor, Nat)  -- Returns slashed amount
slashAuditor auditors aid reason config =
  let found = find (\a => a.id == aid) auditors
  in case found of
    Nothing => notFound Update "slashAuditor" ("Auditor " ++ show aid ++ " not found")
    Just auditor =>
      let slashAmount = (auditor.stakedAmount * config.slashPercentage) `div` 100
          newStake = auditor.stakedAmount `minus` slashAmount
          updated = { status := Slashed
                    , stakedAmount := newStake
                    , slashCount := auditor.slashCount + 1
                    } auditor
          newList = map (\a => if a.id == aid then updated else a) auditors
      in ok Update "slashAuditor"
            ("Slashed " ++ show aid ++ " for " ++ reason ++ ": " ++ show slashAmount)
            (newList, slashAmount)

||| Suspend auditor temporarily
public export
suspendAuditor :
  List Auditor ->
  AuditorId ->
  String ->            -- reason
  FR (List Auditor)
suspendAuditor auditors aid reason =
  let found = find (\a => a.id == aid) auditors
  in case found of
    Nothing => notFound Update "suspendAuditor" ("Auditor " ++ show aid ++ " not found")
    Just auditor =>
      let updated = { status := Suspended } auditor
          newList = map (\a => if a.id == aid then updated else a) auditors
      in ok Update "suspendAuditor"
            ("Suspended " ++ show aid ++ ": " ++ reason)
            newList

||| Reactivate suspended auditor
public export
reactivateAuditor :
  List Auditor ->
  AuditorId ->
  FR (List Auditor)
reactivateAuditor auditors aid =
  let found = find (\a => a.id == aid) auditors
  in case found of
    Nothing => notFound Update "reactivateAuditor" ("Auditor " ++ show aid ++ " not found")
    Just auditor =>
      case auditor.status of
        Suspended =>
          let updated = { status := Active } auditor
              newList = map (\a => if a.id == aid then updated else a) auditors
          in ok Update "reactivateAuditor" ("Reactivated " ++ show aid) newList
        Slashed =>
          fail Update "reactivateAuditor" "Cannot reactivate slashed auditor"
               (InvalidState "Auditor is slashed, not suspended")
        Active =>
          ok Update "reactivateAuditor" ("Already active: " ++ show aid) auditors
        Inactive =>
          let updated = { status := Active } auditor
              newList = map (\a => if a.id == aid then updated else a) auditors
          in ok Update "reactivateAuditor" ("Reactivated " ++ show aid) newList
