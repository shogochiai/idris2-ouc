||| A-Life Economics - Treasury Management
|||
||| Manages OUC's financial reserves:
|||   - ckETH holdings (from user deposits)
|||   - Cycles for operations
|||   - Profit distribution to stakeholders
|||
||| Treasury Flow:
|||   ckETH deposit → Treasury.ckEth
|||                     ↓ (convertToCycles)
|||                   Treasury.operatingCycles
|||                     ↓ (profit allocation)
|||                   Treasury.profitPool
|||                     ↓ (distribution)
|||                   Stakeholder accounts
|||
||| Note: Uses Integer for arbitrary precision arithmetic (GMP via RefC)
module Economics.Treasury

import Data.List

%default total

-- =============================================================================
-- Asset Types
-- =============================================================================

||| Asset denomination
public export
data Asset
  = CkETH      -- Chain-key ETH (1e18 decimals like ETH)
  | ICP        -- Internet Computer Protocol token (1e8 decimals)
  | Cycles     -- ICP Cycles (no decimals, raw count)

public export
Eq Asset where
  CkETH == CkETH = True
  ICP == ICP = True
  Cycles == Cycles = True
  _ == _ = False

public export
Show Asset where
  show CkETH = "ckETH"
  show ICP = "ICP"
  show Cycles = "Cycles"

||| Amount with asset type
public export
record Amount where
  constructor MkAmount
  asset : Asset
  value : Integer

public export
Show Amount where
  show a = show a.value ++ " " ++ show a.asset

||| Zero amount for an asset
public export
zero : Asset -> Amount
zero a = MkAmount a 0

-- =============================================================================
-- Treasury Pools
-- =============================================================================

||| Operating reserve - for canister operations
||| Holds Cycles to pay for:
|||   - HTTP outcalls
|||   - Threshold ECDSA signatures
|||   - Stable memory storage
|||   - Inter-canister calls
public export
record OperatingReserve where
  constructor MkOperatingReserve
  ||| Available cycles for operations
  availableCycles  : Integer
  ||| Reserved cycles (committed but not spent)
  reservedCycles   : Integer
  ||| Total cycles consumed (historical)
  totalConsumed    : Integer
  ||| Low watermark - trigger refill when below
  lowWatermark     : Integer
  ||| High watermark - target after refill
  highWatermark    : Integer

||| Default operating reserve config
public export
defaultOperatingReserve : OperatingReserve
defaultOperatingReserve = MkOperatingReserve
  0                     -- availableCycles
  0                     -- reservedCycles
  0                     -- totalConsumed
  1_000_000_000_000     -- lowWatermark: 1T cycles
  10_000_000_000_000    -- highWatermark: 10T cycles

public export
Show OperatingReserve where
  show r = "Operating{available=" ++ show r.availableCycles
        ++ ", reserved=" ++ show r.reservedCycles ++ "}"

||| Profit pool - for stakeholder distribution
public export
record ProfitPool where
  constructor MkProfitPool
  ||| Undistributed profits (in ckETH wei)
  undistributed    : Integer
  ||| Total profits distributed (historical)
  totalDistributed : Integer
  ||| Last distribution timestamp
  lastDistributedAt : Integer

public export
defaultProfitPool : ProfitPool
defaultProfitPool = MkProfitPool 0 0 0

public export
Show ProfitPool where
  show p = "Profit{undistributed=" ++ show p.undistributed
        ++ ", distributed=" ++ show p.totalDistributed ++ "}"

-- =============================================================================
-- Treasury State
-- =============================================================================

||| Main treasury state
public export
record Treasury where
  constructor MkTreasury
  ||| ckETH balance (in wei, 1e18 = 1 ckETH)
  ckEthBalance     : Integer
  ||| ICP balance (in e8s, 1e8 = 1 ICP)
  icpBalance       : Integer
  ||| Operating reserve (Cycles)
  operating        : OperatingReserve
  ||| Profit pool (ckETH)
  profit           : ProfitPool
  ||| Allocation ratio: % of income to operating (0-100)
  operatingRatio   : Integer
  ||| Last update timestamp
  updatedAt        : Integer

||| Initial treasury state
public export
initialTreasury : Treasury
initialTreasury = MkTreasury
  0                        -- ckEthBalance
  0                        -- icpBalance
  defaultOperatingReserve  -- operating
  defaultProfitPool        -- profit
  70                       -- operatingRatio: 70% to operations
  0                        -- updatedAt

public export
Show Treasury where
  show t = "Treasury{ckETH=" ++ show t.ckEthBalance
        ++ ", ICP=" ++ show t.icpBalance
        ++ ", " ++ show t.operating
        ++ ", " ++ show t.profit ++ "}"

-- =============================================================================
-- Deposit Processing
-- =============================================================================

||| Result of processing a ckETH deposit
public export
record DepositResult where
  constructor MkDepositResult
  ||| Updated treasury
  treasury         : Treasury
  ||| Amount to convert to cycles
  toOperating      : Integer
  ||| Amount to profit pool
  toProfit         : Integer

||| Process incoming ckETH deposit
||| Splits between operating reserve and profit pool based on ratio
public export
processDeposit :
  Treasury ->
  Integer ->       -- ckETH amount (wei)
  Integer ->       -- currentTime
  DepositResult
processDeposit t amount now =
  let -- Calculate split based on operatingRatio
      toOps = (amount * t.operatingRatio) `div` 100
      toProfit = amount - toOps
      -- Update balances
      newCkEth = t.ckEthBalance + amount
      newProfit = MkProfitPool
        (t.profit.undistributed + toProfit)
        t.profit.totalDistributed
        t.profit.lastDistributedAt
      newTreasury = MkTreasury
        newCkEth
        t.icpBalance
        t.operating
        newProfit
        t.operatingRatio
        now
  in MkDepositResult newTreasury toOps toProfit

-- =============================================================================
-- Cycles Management
-- =============================================================================

||| Result of cycles operation
public export
data CyclesResult
  = CyclesOk Treasury
  | InsufficientCycles Integer Integer  -- requested, available

||| Reserve cycles for an operation
public export
reserveCycles :
  Treasury ->
  Integer ->       -- amount to reserve
  CyclesResult
reserveCycles t amount =
  let available = t.operating.availableCycles
  in if available >= amount
     then let ops = t.operating
              newOps = MkOperatingReserve
                (ops.availableCycles - amount)
                (ops.reservedCycles + amount)
                ops.totalConsumed
                ops.lowWatermark
                ops.highWatermark
              newT = MkTreasury
                t.ckEthBalance t.icpBalance newOps t.profit t.operatingRatio t.updatedAt
          in CyclesOk newT
     else InsufficientCycles amount available

||| Commit reserved cycles (operation completed)
public export
commitCycles :
  Treasury ->
  Integer ->       -- amount to commit
  Treasury
commitCycles t amount =
  let ops = t.operating
      newOps = MkOperatingReserve
        ops.availableCycles
        (ops.reservedCycles - amount)
        (ops.totalConsumed + amount)
        ops.lowWatermark
        ops.highWatermark
  in MkTreasury t.ckEthBalance t.icpBalance newOps t.profit t.operatingRatio t.updatedAt

||| Release reserved cycles (operation cancelled)
public export
releaseCycles :
  Treasury ->
  Integer ->       -- amount to release
  Treasury
releaseCycles t amount =
  let ops = t.operating
      newOps = MkOperatingReserve
        (ops.availableCycles + amount)
        (ops.reservedCycles - amount)
        ops.totalConsumed
        ops.lowWatermark
        ops.highWatermark
  in MkTreasury t.ckEthBalance t.icpBalance newOps t.profit t.operatingRatio t.updatedAt

||| Add cycles to operating reserve
public export
addCycles :
  Treasury ->
  Integer ->       -- cycles amount
  Integer ->       -- currentTime
  Treasury
addCycles t cycles now =
  let ops = t.operating
      newOps = MkOperatingReserve
        (ops.availableCycles + cycles)
        ops.reservedCycles
        ops.totalConsumed
        ops.lowWatermark
        ops.highWatermark
  in MkTreasury t.ckEthBalance t.icpBalance newOps t.profit t.operatingRatio now

||| Check if operating reserve needs refill
public export
needsRefill : Treasury -> Bool
needsRefill t =
  t.operating.availableCycles < t.operating.lowWatermark

||| Calculate refill amount needed
public export
refillAmount : Treasury -> Integer
refillAmount t =
  if needsRefill t
  then t.operating.highWatermark - t.operating.availableCycles
  else 0

-- =============================================================================
-- Conversion Rates
-- =============================================================================

||| Conversion rate record
public export
record ConversionRate where
  constructor MkConversionRate
  ||| Source asset
  from       : Asset
  ||| Target asset
  to         : Asset
  ||| Rate (multiplier, scaled by 1e12 for precision)
  rate       : Integer
  ||| Timestamp of rate
  timestamp  : Integer

||| Scale factor for rate precision
public export
RATE_SCALE : Integer
RATE_SCALE = 1_000_000_000_000  -- 1e12

||| Default ckETH -> ICP rate (placeholder)
||| Real rate should come from DEX or oracle
public export
defaultCkEthToIcpRate : ConversionRate
defaultCkEthToIcpRate = MkConversionRate CkETH ICP
  200_000_000_000_000   -- ~200 ICP per ETH (scaled)
  0

||| Default ICP -> Cycles rate
||| CMC rate: ~1 ICP = 1T cycles (varies with SDR)
public export
defaultIcpToCyclesRate : ConversionRate
defaultIcpToCyclesRate = MkConversionRate ICP Cycles
  1_000_000_000_000     -- 1T cycles per ICP (scaled)
  0

||| Apply conversion rate
public export
convert : ConversionRate -> Integer -> Integer
convert r amount = (amount * r.rate) `div` RATE_SCALE

-- =============================================================================
-- Profit Distribution
-- =============================================================================

||| Stakeholder share record
public export
record StakeholderShare where
  constructor MkStakeholderShare
  ||| Stakeholder identifier
  stakeholderId    : String
  ||| Share percentage (0-100, scaled by 100 for 2 decimal places)
  sharePercent     : Integer  -- e.g., 2500 = 25.00%
  ||| Total received (historical)
  totalReceived    : Integer

||| Distribution result
public export
record DistributionResult where
  constructor MkDistributionResult
  ||| Updated treasury
  treasury         : Treasury
  ||| Updated stakeholder shares
  shares           : List StakeholderShare
  ||| Amount distributed this round
  distributed      : Integer

||| Calculate distribution amount for a stakeholder
public export
calculateShare : Integer -> StakeholderShare -> Integer
calculateShare totalAmount sh =
  (totalAmount * sh.sharePercent) `div` 10000

||| Distribute profits to stakeholders
public export
distributeProfit :
  Treasury ->
  List StakeholderShare ->
  Integer ->       -- currentTime
  DistributionResult
distributeProfit t shares now =
  let available = t.profit.undistributed
      -- Calculate each share
      updateShare : StakeholderShare -> StakeholderShare
      updateShare s =
        let amt = calculateShare available s
        in MkStakeholderShare s.stakeholderId s.sharePercent (s.totalReceived + amt)
      newShares = map updateShare shares
      -- Update treasury
      newProfit = MkProfitPool
        0  -- undistributed cleared
        (t.profit.totalDistributed + available)
        now
      newT = MkTreasury t.ckEthBalance t.icpBalance t.operating newProfit t.operatingRatio now
  in MkDistributionResult newT newShares available

-- =============================================================================
-- Treasury Statistics
-- =============================================================================

||| Treasury statistics
public export
record TreasuryStats where
  constructor MkTreasuryStats
  ||| Total value in ckETH equivalent
  totalValueCkEth  : Integer
  ||| Cycles runway (days at current burn rate)
  cyclesRunwayDays : Integer
  ||| Operating pool utilization %
  operatingUtil    : Integer
  ||| Profit pool pending distribution
  pendingProfit    : Integer

||| Calculate treasury statistics
public export
getTreasuryStats :
  Treasury ->
  Integer ->       -- daily cycles burn rate
  TreasuryStats
getTreasuryStats t dailyBurn =
  let totalCkEth = t.ckEthBalance + (t.profit.undistributed)
      runway = if dailyBurn > 0
               then t.operating.availableCycles `div` dailyBurn
               else 999  -- essentially infinite
      totalOps = t.operating.availableCycles + t.operating.reservedCycles
      util = if t.operating.highWatermark > 0
             then (totalOps * 100) `div` t.operating.highWatermark
             else 0
  in MkTreasuryStats totalCkEth runway util t.profit.undistributed
