||| Rewards Module
|||
||| Manages reward distribution for auditors who complete reviews.
||| Implements:
||| - Fee collection from proposal submissions
||| - Reward calculation based on review quality
||| - Distribution scheduling
||| - Treasury management
module Rewards.Core

import FRMonad.Core
import OUC.Functions.Core
import OUC.Types.Validated
import Data.List
import Data.Nat

%default total

-- =============================================================================
-- Reward Types
-- =============================================================================

||| Token amounts (in smallest unit)
public export
TokenAmount : Type
TokenAmount = Nat

||| Reward distribution record
public export
record RewardDistribution where
  constructor MkRewardDistribution
  recipientId   : AuditorId
  proposalId    : ProposalId
  amount        : TokenAmount
  reason        : String
  distributedAt : Nat
  txRef         : String      -- Transaction reference for evidence

public export
Show RewardDistribution where
  show r = "Reward{to=" ++ show r.recipientId
        ++ ", amount=" ++ show r.amount
        ++ ", for=" ++ show r.proposalId ++ "}"

||| Fee collection record
public export
record FeeCollection where
  constructor MkFeeCollection
  proposalId  : ProposalId
  payer       : ValidatedPrincipal
  amount      : TokenAmount
  collectedAt : Nat

public export
Show FeeCollection where
  show f = "Fee{from=" ++ show f.payer
        ++ ", amount=" ++ show f.amount
        ++ ", for=" ++ show f.proposalId ++ "}"

-- =============================================================================
-- Rewards Configuration
-- =============================================================================

||| Configuration for reward distribution
public export
record RewardsConfig where
  constructor MkRewardsConfig
  proposalFee        : TokenAmount  -- Fee charged per proposal
  auditorRewardShare : Nat          -- Percentage to auditors (0-100)
  treasuryShare      : Nat          -- Percentage to treasury (0-100)
  qualityBonus       : TokenAmount  -- Bonus for high-quality reviews
  speedBonus         : TokenAmount  -- Bonus for fast turnaround

||| Default rewards configuration
public export
defaultRewardsConfig : RewardsConfig
defaultRewardsConfig = MkRewardsConfig 100 80 20 10 5

-- =============================================================================
-- Treasury State
-- =============================================================================

||| Treasury state for holding collected fees
public export
record Treasury where
  constructor MkTreasury
  balance        : TokenAmount
  totalCollected : TokenAmount
  totalDistributed : TokenAmount

||| Initial treasury
public export
emptyTreasury : Treasury
emptyTreasury = MkTreasury 0 0 0

-- =============================================================================
-- Rewards State
-- =============================================================================

||| Complete rewards state
public export
record RewardsState where
  constructor MkRewardsState
  treasury      : Treasury
  fees          : List FeeCollection
  distributions : List RewardDistribution
  pendingRewards : List (AuditorId, TokenAmount, ProposalId)
  config        : RewardsConfig

||| Initial rewards state
public export
initialRewardsState : RewardsConfig -> RewardsState
initialRewardsState config = MkRewardsState emptyTreasury [] [] [] config

-- =============================================================================
-- Reward Calculations
-- =============================================================================

||| Calculate auditor reward for a review
public export
calculateReward :
  RewardsConfig ->
  TokenAmount ->       -- Fee collected for proposal
  Bool ->              -- Was review high quality?
  Bool ->              -- Was review fast?
  TokenAmount
calculateReward config fee highQuality fast =
  let baseReward = divNatNZ (fee * config.auditorRewardShare) 100 ItIsSucc
  in let qualityBonus = if highQuality then config.qualityBonus else 0
     in let speedBonus = if fast then config.speedBonus else 0
        in baseReward + qualityBonus + speedBonus

||| Calculate treasury deposit from fee
public export
calculateTreasuryDeposit : RewardsConfig -> TokenAmount -> TokenAmount
calculateTreasuryDeposit config fee = divNatNZ (fee * config.treasuryShare) 100 ItIsSucc

-- =============================================================================
-- Reward Operations (FRC-compliant)
-- =============================================================================

||| Collect fee for proposal submission
public export
collectFee :
  RewardsState ->
  ProposalId ->
  ValidatedPrincipal ->
  TokenAmount ->
  Nat ->               -- currentTime
  FR RewardsState
collectFee state pid payer amount now =
  if amount < state.config.proposalFee
    then fail Update "collectFee" "Insufficient fee"
              (Unauthorized ("Fee " ++ show amount ++ " < " ++ show state.config.proposalFee))
    else
      let fee = MkFeeCollection pid payer amount now
      in let treasuryDeposit = calculateTreasuryDeposit state.config amount
         in let newTreasury = MkTreasury
                  (state.treasury.balance + treasuryDeposit)
                  (state.treasury.totalCollected + amount)
                  state.treasury.totalDistributed
            in let newState = MkRewardsState
                     newTreasury
                     (fee :: state.fees)
                     state.distributions
                     state.pendingRewards
                     state.config
               in ok Update "collectFee"
                     ("Collected " ++ show amount ++ " for " ++ show pid)
                     newState

||| Queue reward for auditor
public export
queueReward :
  RewardsState ->
  AuditorId ->
  ProposalId ->
  Bool ->              -- highQuality
  Bool ->              -- fast
  FR RewardsState
queueReward state aid pid highQuality fast =
  let feeOpt = find (\f => f.proposalId == pid) state.fees
  in case feeOpt of
    Nothing => notFound Update "queueReward" ("No fee collected for " ++ show pid)
    Just fee =>
      let reward = calculateReward state.config fee.amount highQuality fast
      in let pending = (aid, reward, pid)
         in let newState = MkRewardsState
                  state.treasury
                  state.fees
                  state.distributions
                  (pending :: state.pendingRewards)
                  state.config
            in ok Update "queueReward"
                  ("Queued " ++ show reward ++ " for " ++ show aid)
                  newState

||| Distribute a pending reward
public export
distributeReward :
  RewardsState ->
  AuditorId ->
  ProposalId ->
  String ->            -- txRef
  Nat ->               -- currentTime
  FR (RewardsState, TokenAmount)
distributeReward state aid pid txRef now =
  let pending = find (\x => case x of (a, _, p) => a == aid && p == pid) state.pendingRewards
  in case pending of
    Nothing => notFound Update "distributeReward"
               ("No pending reward for " ++ show aid ++ " on " ++ show pid)
    Just (_, amount, _) =>
      if amount > state.treasury.balance
        then fail Update "distributeReward" "Insufficient treasury balance"
                  (InvalidState ("Treasury has " ++ show state.treasury.balance ++ " but need " ++ show amount))
        else
          let dist = MkRewardDistribution aid pid amount "Review reward" now txRef
          in let newPending = filter (\x => case x of (a, _, p) => not (a == aid && p == pid))
                                     state.pendingRewards
             in let newTreasury = MkTreasury
                      (state.treasury.balance `minus` amount)
                      state.treasury.totalCollected
                      (state.treasury.totalDistributed + amount)
                in let newState = MkRewardsState
                         newTreasury
                         state.fees
                         (dist :: state.distributions)
                         newPending
                         state.config
                   in ok Update "distributeReward"
                         ("Distributed " ++ show amount ++ " to " ++ show aid)
                         (newState, amount)

||| Get pending reward for auditor
public export
getPendingReward :
  RewardsState ->
  AuditorId ->
  FR TokenAmount
getPendingReward state aid =
  let pending = filter (\x => case x of (a, _, _) => a == aid) state.pendingRewards
  in let sum = foldl (\acc, x => case x of (_, amt, _) => acc + amt) 0 pending
     in ok Query "getPendingReward" ("Pending for " ++ show aid ++ ": " ++ show sum) sum

||| Get total distributed to auditor
public export
getTotalDistributed :
  RewardsState ->
  AuditorId ->
  FR TokenAmount
getTotalDistributed state aid =
  let dists = filter (\d => d.recipientId == aid) state.distributions
  in let sum = foldl (\acc, d => acc + d.amount) 0 dists
     in ok Query "getTotalDistributed" ("Total for " ++ show aid ++ ": " ++ show sum) sum

||| Get treasury balance
public export
getTreasuryBalance : RewardsState -> FR TokenAmount
getTreasuryBalance state =
  ok Query "getTreasuryBalance" ("Balance: " ++ show state.treasury.balance) state.treasury.balance
