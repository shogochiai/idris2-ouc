||| A-Life Economics - Protocol Account Management
|||
||| Manages per-protocol balance, tier status, and lifecycle.
||| Implements donation-driven tier upgrades and automatic downgrades.
|||
||| Key Operations:
|||   - donate: Add cycles, potentially upgrade tier
|||   - dailyDeduction: Deduct daily cost, potentially downgrade
|||   - catchUpSync: Calculate cost for historical sync on revival
module Economics.ProtocolAccount

import Economics.Tier
import MultiChain.Registry
import Data.List
import Data.Nat

%default total

-- Helper for safe division (returns 0 if divisor is 0)
safeDiv : Nat -> Nat -> Nat
safeDiv n m = case m of
  Z => 0
  S k => divNatNZ n (S k) ItIsSucc

-- =============================================================================
-- Protocol Account
-- =============================================================================

||| Protocol account for A-Life Economics
||| Tracks balance and tier status for each registered protocol
public export
record ProtocolAccount where
  constructor MkProtocolAccount
  ||| Protocol identifier (OU contract address on primary chain)
  protocolId     : EvmAddress
  ||| Chain ID where protocol is registered
  chainId        : ChainId
  ||| Current cycles balance
  balance        : Nat
  ||| Current service tier
  currentTier    : Tier
  ||| Last synced block number
  lastSyncBlock  : Nat
  ||| Last sync timestamp (nanoseconds)
  lastSyncAt     : Nat
  ||| Account created timestamp
  createdAt      : Nat
  ||| Account updated timestamp
  updatedAt      : Nat
  ||| Tier expiration (Nothing = perpetual archive)
  expiresAt      : Maybe Nat

public export
Show ProtocolAccount where
  show acc = "Protocol{" ++ acc.protocolId.hex
          ++ ", tier=" ++ show acc.currentTier
          ++ ", balance=" ++ show acc.balance ++ "}"

public export
Eq ProtocolAccount where
  a1 == a2 = a1.protocolId == a2.protocolId && a1.chainId == a2.chainId

-- =============================================================================
-- Donation Result
-- =============================================================================

||| Result of a donation operation
public export
record DonationResult where
  constructor MkDonationResult
  ||| Updated account
  account        : ProtocolAccount
  ||| Previous tier (before donation)
  previousTier   : Tier
  ||| New tier (after donation)
  newTier        : Tier
  ||| Whether tier was upgraded
  tierUpgraded   : Bool
  ||| Catch-up sync cost (if tier upgraded from Archive)
  catchUpCost    : Nat
  ||| Months of service at new tier
  monthsAtTier   : Nat

public export
Show DonationResult where
  show r = "Donation{" ++ show r.previousTier ++ " -> " ++ show r.newTier
        ++ ", upgraded=" ++ show r.tierUpgraded
        ++ ", catchUp=" ++ show r.catchUpCost ++ "}"

-- =============================================================================
-- Account Creation
-- =============================================================================

||| Create new protocol account (starts at Archive tier)
public export
createAccount :
  EvmAddress ->     -- protocolId
  ChainId ->        -- chainId
  Nat ->            -- currentTime
  ProtocolAccount
createAccount protocolId chainId now =
  MkProtocolAccount
    protocolId
    chainId
    0                -- balance starts at 0
    Archive          -- all start at Archive tier
    0                -- lastSyncBlock
    now              -- lastSyncAt
    now              -- createdAt
    now              -- updatedAt
    Nothing          -- no expiry (perpetual archive)

-- =============================================================================
-- Catch-up Sync Cost Calculation
-- =============================================================================

||| Calculate catch-up sync cost based on time since last sync
||| Used when reviving from Archive to higher tier
|||
||| Formula:
|||   blocksToSync = monthsArchived * 30 * 24 * 60 * 5 (12sec/block)
|||   callsNeeded = blocksToSync / 1000 (1000 blocks/call)
|||   cyclesCost = callsNeeded * 500_000_000 (0.5B cycles/call)
public export
calculateCatchUpCost :
  Nat ->            -- lastSyncAt (nanoseconds)
  Nat ->            -- currentTime (nanoseconds)
  Nat
calculateCatchUpCost lastSync now =
  let -- Time difference in seconds
      timeDiffNs = minus now lastSync
      timeDiffSec = safeDiv timeDiffNs 1_000_000_000
      -- Blocks to sync (assuming ~12 sec/block on Ethereum)
      blocksToSync = safeDiv timeDiffSec 12
      -- HTTP Outcall calls needed (1000 blocks per call with eth_getLogs)
      callsNeeded = safeDiv blocksToSync 1000 + 1
      -- Cost: 0.5B cycles per call
      cyclesCost = callsNeeded * 500_000_000
  in cyclesCost

-- =============================================================================
-- Donation Processing
-- =============================================================================

||| Process donation to protocol account
||| May trigger tier upgrade and catch-up sync
public export
donate :
  ProtocolAccount ->
  Nat ->            -- amount (cycles)
  Nat ->            -- currentTime
  DonationResult
donate acc amount now =
  let -- Add donation to balance
      newBalance = acc.balance + amount
      -- Calculate affordable tier
      previousTier = acc.currentTier
      newTier = calculateAffordableTier newBalance
      -- Check if tier upgraded
      tierUpgraded = newTier > previousTier
      -- Calculate catch-up cost (only if upgrading from Archive)
      catchUpCost = if tierUpgraded && previousTier == Archive
                    then calculateCatchUpCost acc.lastSyncAt now
                    else 0
      -- Deduct catch-up cost from balance
      balanceAfterCatchUp = minus newBalance catchUpCost
      -- Recalculate tier after catch-up deduction
      finalTier = if catchUpCost > 0
                  then calculateAffordableTier balanceAfterCatchUp
                  else newTier
      -- Calculate months at tier
      monthsAtTier = calculateMonthsAtTier balanceAfterCatchUp finalTier
      -- Set expiration (30 days from now if above Archive)
      newExpiry = if finalTier > Archive
                  then Just (now + 30 * 24 * 60 * 60 * 1_000_000_000)
                  else Nothing
      -- Update account
      updated = { balance := balanceAfterCatchUp
                , currentTier := finalTier
                , updatedAt := now
                , expiresAt := newExpiry
                } acc
  in MkDonationResult updated previousTier finalTier tierUpgraded catchUpCost monthsAtTier

-- =============================================================================
-- Daily Tier Management
-- =============================================================================

||| Deduction result from daily processing
public export
record DeductionResult where
  constructor MkDeductionResult
  account        : ProtocolAccount
  previousTier   : Tier
  newTier        : Tier
  tierDowngraded : Bool
  amountDeducted : Nat

public export
Show DeductionResult where
  show r = "Deduction{" ++ show r.previousTier ++ " -> " ++ show r.newTier
        ++ ", deducted=" ++ show r.amountDeducted ++ "}"

||| Process daily cost deduction
||| May trigger tier downgrade if balance insufficient
public export
dailyDeduction :
  ProtocolAccount ->
  Nat ->            -- currentTime
  DeductionResult
dailyDeduction acc now =
  let previousTier = acc.currentTier
      dailyCost = tierDailyCost previousTier
  in if acc.balance >= dailyCost
     then -- Sufficient balance: deduct and stay at tier
       let updated = { balance := minus acc.balance dailyCost
                     , updatedAt := now
                     } acc
       in MkDeductionResult updated previousTier previousTier False dailyCost
     else -- Insufficient balance: downgrade to affordable tier
       let newTier = calculateAffordableTier acc.balance
           newDailyCost = tierDailyCost newTier
           deducted = if acc.balance >= newDailyCost
                      then newDailyCost
                      else acc.balance
           updated = { balance := minus acc.balance deducted
                     , currentTier := newTier
                     , updatedAt := now
                     , expiresAt := if newTier == Archive then Nothing else acc.expiresAt
                     } acc
       in MkDeductionResult updated previousTier newTier True deducted

-- =============================================================================
-- Sync Operations
-- =============================================================================

||| Update sync progress after successful sync
public export
recordSync :
  ProtocolAccount ->
  Nat ->            -- blockNumber
  Nat ->            -- currentTime
  ProtocolAccount
recordSync acc blockNum now =
  { lastSyncBlock := blockNum
  , lastSyncAt := now
  , updatedAt := now
  } acc

||| Check if sync is due based on tier interval
public export
isSyncDue :
  ProtocolAccount ->
  Nat ->            -- currentTime (nanoseconds)
  Bool
isSyncDue acc now =
  let interval = tierSyncInterval acc.currentTier
      intervalNs = interval * 1_000_000_000
      timeSinceSync = minus now acc.lastSyncAt
  in timeSinceSync >= intervalNs

-- =============================================================================
-- Account Registry
-- =============================================================================

||| Registry of all protocol accounts
public export
record AccountRegistry where
  constructor MkAccountRegistry
  accounts    : List ProtocolAccount
  totalCycles : Nat
  lastUpdated : Nat

||| Empty registry
public export
emptyRegistry : AccountRegistry
emptyRegistry = MkAccountRegistry [] 0 0

||| Find account by protocol ID
public export
findAccount : AccountRegistry -> EvmAddress -> Maybe ProtocolAccount
findAccount reg protocolId = find (\a => a.protocolId == protocolId) reg.accounts

||| Add or update account in registry
public export
upsertAccount : AccountRegistry -> ProtocolAccount -> Nat -> AccountRegistry
upsertAccount reg acc now =
  let others = filter (\a => a.protocolId /= acc.protocolId) reg.accounts
      newTotal = foldr (+) 0 (map (.balance) (acc :: others))
  in MkAccountRegistry (acc :: others) newTotal now

||| Get accounts by tier
public export
getAccountsByTier : AccountRegistry -> Tier -> List ProtocolAccount
getAccountsByTier reg tier = filter (\a => a.currentTier == tier) reg.accounts

||| Get accounts due for sync
public export
getAccountsDueForSync : AccountRegistry -> Nat -> List ProtocolAccount
getAccountsDueForSync reg now = filter (\a => isSyncDue a now) reg.accounts

||| Count accounts by tier
public export
countByTier : AccountRegistry -> Tier -> Nat
countByTier reg tier = length (getAccountsByTier reg tier)

||| Get tier distribution
public export
record TierDistribution where
  constructor MkTierDistribution
  archiveCount  : Nat
  economyCount  : Nat
  standardCount : Nat
  realtimeCount : Nat
  totalCount    : Nat

public export
Show TierDistribution where
  show d = "TierDist{archive=" ++ show d.archiveCount
        ++ ", economy=" ++ show d.economyCount
        ++ ", standard=" ++ show d.standardCount
        ++ ", realtime=" ++ show d.realtimeCount ++ "}"

||| Calculate tier distribution
public export
getTierDistribution : AccountRegistry -> TierDistribution
getTierDistribution reg =
  MkTierDistribution
    (countByTier reg Archive)
    (countByTier reg Economy)
    (countByTier reg Standard)
    (countByTier reg RealTime)
    (length reg.accounts)

-- =============================================================================
-- Batch Operations (for Timer)
-- =============================================================================

||| Process daily deductions for all accounts
public export
processDailyDeductions :
  AccountRegistry ->
  Nat ->            -- currentTime
  (AccountRegistry, List DeductionResult)
processDailyDeductions reg now =
  let results = map (\acc => dailyDeduction acc now) reg.accounts
      updatedAccounts = map (.account) results
      newTotal = foldr (+) 0 (map (.balance) updatedAccounts)
  in (MkAccountRegistry updatedAccounts newTotal now, results)

||| Get all accounts that need sync now
public export
getScheduledSyncs :
  AccountRegistry ->
  Nat ->            -- currentTime
  List ProtocolAccount
getScheduledSyncs reg now = getAccountsDueForSync reg now

-- =============================================================================
-- Serialization
-- =============================================================================

||| Serialize ProtocolAccount to string
||| Format: protocolId|chainId|balance|tier|lastSyncBlock|lastSyncAt|createdAt|updatedAt|expiresAt
public export
serializeAccount : ProtocolAccount -> String
serializeAccount acc =
  acc.protocolId.hex ++ "|" ++
  show acc.chainId.value ++ "|" ++
  show acc.balance ++ "|" ++
  serializeTier acc.currentTier ++ "|" ++
  show acc.lastSyncBlock ++ "|" ++
  show acc.lastSyncAt ++ "|" ++
  show acc.createdAt ++ "|" ++
  show acc.updatedAt ++ "|" ++
  (case acc.expiresAt of
    Nothing => "none"
    Just t  => show t)

||| Storage key for account
public export
keyAccount : EvmAddress -> String
keyAccount addr = "economics:account:" ++ addr.hex

-- =============================================================================
-- EVM Fee Sync (A-Life Economics Option B)
-- =============================================================================

||| ETH to Cycles conversion rate
||| 1 ETH (1e18 wei) = 10 trillion cycles (1e13)
||| This gives: 0.001 ETH = 10 billion cycles (~¥10,000 worth)
|||
||| Rationale:
|||   - 1 trillion cycles ≈ ¥1,000
|||   - ETH price fluctuates, but ~¥300,000/ETH is reasonable
|||   - 0.001 ETH ≈ ¥300 → 300 billion cycles? No, too much
|||   - Better: 0.01 ETH ≈ 1 month Standard tier (300B cycles)
|||   - Rate: 1e18 wei → 3e13 cycles (30 trillion per ETH)
public export
weiToCyclesRate : Nat
weiToCyclesRate = 30000  -- cycles per 1e12 wei (0.000001 ETH)

||| Convert wei to cycles
||| wei * rate / 1e12 = cycles
||| To avoid overflow: (wei / 1e12) * rate
public export
weiToCycles : Nat -> Nat
weiToCycles weiAmount =
  let -- Divide by 1e12 first to avoid large numbers
      scaledWei = safeDiv weiAmount 1000000000000  -- 1e12
  in scaledWei * weiToCyclesRate

||| EVM Fee state for a protocol
||| Tracks the last synced EVM balance to compute delta
public export
record EvmFeeState where
  constructor MkEvmFeeState
  ||| Last synced EVM balance (wei)
  lastSyncedBalance : Nat
  ||| Total ETH deposited (wei) - cumulative
  totalDeposited    : Nat
  ||| Total cycles credited from ETH
  totalCredited     : Nat
  ||| Last sync timestamp
  lastFeeSyncAt     : Nat

||| Initial EVM fee state
public export
initialEvmFeeState : EvmFeeState
initialEvmFeeState = MkEvmFeeState 0 0 0 0

public export
Show EvmFeeState where
  show s = "EvmFee{synced=" ++ show s.lastSyncedBalance
        ++ ", deposited=" ++ show s.totalDeposited
        ++ ", credited=" ++ show s.totalCredited ++ "}"

||| Result of syncing EVM fee balance
public export
record FeeSyncResult where
  constructor MkFeeSyncResult
  ||| Updated fee state
  feeState        : EvmFeeState
  ||| Updated protocol account (with new balance)
  account         : ProtocolAccount
  ||| New deposit detected (wei)
  newDeposit      : Nat
  ||| Cycles credited from new deposit
  cyclesCredited  : Nat
  ||| Whether tier was upgraded
  tierUpgraded    : Bool
  ||| Previous tier
  previousTier    : Tier
  ||| New tier
  newTier         : Tier

public export
Show FeeSyncResult where
  show r = "FeeSync{newDeposit=" ++ show r.newDeposit
        ++ ", credited=" ++ show r.cyclesCredited
        ++ ", " ++ show r.previousTier ++ " -> " ++ show r.newTier ++ "}"

||| Sync EVM fee balance to protocol account
|||
||| Called when we read the EVM-side fee balance via HTTP outcall.
||| Computes the delta (new deposits) and credits cycles to the account.
|||
||| @param feeState Current EVM fee state
||| @param account Current protocol account
||| @param evmBalance Current EVM-side balance (wei) from eth_call
||| @param currentTime Current timestamp
public export
syncEvmFeeBalance :
  EvmFeeState ->
  ProtocolAccount ->
  Nat ->              -- evmBalance (wei)
  Nat ->              -- currentTime
  FeeSyncResult
syncEvmFeeBalance feeState account evmBalance now =
  let -- Calculate new deposit (delta from last sync)
      -- Note: EVM balance only increases (deposits), never decreases
      -- So if evmBalance > lastSynced, we have new deposits
      newDeposit = if evmBalance > feeState.lastSyncedBalance
                   then evmBalance `minus` feeState.lastSyncedBalance
                   else 0
      -- Convert to cycles
      newCycles = weiToCycles newDeposit
      -- Credit to account (similar to donate)
      donationResult = donate account newCycles now
      -- Update fee state
      newFeeState = MkEvmFeeState
        evmBalance
        (feeState.totalDeposited + newDeposit)
        (feeState.totalCredited + newCycles)
        now
  in MkFeeSyncResult
       newFeeState
       donationResult.account
       newDeposit
       newCycles
       donationResult.tierUpgraded
       donationResult.previousTier
       donationResult.newTier

||| Check if EVM fee sync is needed
||| Sync is needed if:
|||   1. Never synced before (lastFeeSyncAt == 0)
|||   2. Enough time has passed (e.g., 1 hour)
public export
isFeeSyncDue :
  EvmFeeState ->
  Nat ->              -- currentTime
  Nat ->              -- syncInterval (e.g., 3600 for 1 hour)
  Bool
isFeeSyncDue feeState now interval =
  if feeState.lastFeeSyncAt == 0
    then True  -- Never synced
    else (now `minus` feeState.lastFeeSyncAt) >= interval

||| Fee sync interval (1 hour in nanoseconds)
public export
feeSyncIntervalNs : Nat
feeSyncIntervalNs = 3600 * 1000000000

||| Fee sync interval (1 hour in seconds)
public export
feeSyncIntervalSec : Nat
feeSyncIntervalSec = 3600
