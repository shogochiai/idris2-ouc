||| A-Life Economics - Cycles Minting
|||
||| Handles conversion of ckETH → ICP → Cycles via:
|||   1. DEX swap (ckETH → ICP) - e.g., ICPSwap, Sonic
|||   2. CMC mint (ICP → Cycles)
|||
||| CMC (Cycles Minting Canister): rkp4c-7iaaa-aaaaa-aaaca-cai
|||
||| Flow:
|||   ckETH (in OUC account)
|||     ↓ ICRC-2 approve + DEX swap
|||   ICP (in OUC account)
|||     ↓ notify_top_up to CMC
|||   Cycles (in canister balance)
|||
||| Note: Uses Integer for arbitrary precision arithmetic (GMP via RefC)
module Economics.CyclesMinting

import Data.List

%default total

-- =============================================================================
-- Canister IDs
-- =============================================================================

||| CMC (Cycles Minting Canister) principal
||| This is a system canister that converts ICP to Cycles
public export
CMC_CANISTER : String
CMC_CANISTER = "rkp4c-7iaaa-aaaaa-aaaca-cai"

||| ICP Ledger canister
public export
ICP_LEDGER : String
ICP_LEDGER = "ryjl3-tyaaa-aaaaa-aaaba-cai"

||| ckETH Ledger canister
public export
CKETH_LEDGER : String
CKETH_LEDGER = "ss2fx-dyaaa-aaaar-qacoq-cai"

-- =============================================================================
-- Conversion Types
-- =============================================================================

||| State of a cycles minting operation
public export
data MintingState
  = MintingPending           -- Waiting to start
  | SwapInitiated Integer     -- DEX swap started (swap ID)
  | SwapCompleted Integer Integer  -- Swap done (ICP amount, block)
  | TransferToSubaccount Integer  -- Transferring to CMC subaccount
  | NotifyingCMC Integer      -- Calling notify_top_up
  | MintingCompleted Integer  -- Cycles received
  | MintingFailed String     -- Error occurred

public export
Show MintingState where
  show MintingPending = "Pending"
  show (SwapInitiated id) = "SwapInitiated(" ++ show id ++ ")"
  show (SwapCompleted icp block) = "SwapCompleted(" ++ show icp ++ " ICP)"
  show (TransferToSubaccount amt) = "Transferring(" ++ show amt ++ ")"
  show (NotifyingCMC block) = "NotifyingCMC(" ++ show block ++ ")"
  show (MintingCompleted cycles) = "Completed(" ++ show cycles ++ " cycles)"
  show (MintingFailed err) = "Failed: " ++ err

||| Minting request record
public export
record MintingRequest where
  constructor MkMintingRequest
  ||| Request ID
  requestId      : Integer
  ||| Amount of ckETH to convert (wei)
  ckEthAmount    : Integer
  ||| Expected ICP amount (e8s) - based on quote
  expectedIcp    : Integer
  ||| Minimum acceptable ICP (slippage protection)
  minIcp         : Integer
  ||| Current state
  state          : MintingState
  ||| Created timestamp
  createdAt      : Integer
  ||| Last updated timestamp
  updatedAt      : Integer

public export
Show MintingRequest where
  show r = "MintRequest{id=" ++ show r.requestId
        ++ ", ckETH=" ++ show r.ckEthAmount
        ++ ", state=" ++ show r.state ++ "}"

-- =============================================================================
-- CMC Subaccount Calculation
-- =============================================================================

||| CMC requires deposits to a specific subaccount
||| Subaccount = SHA256(canister_id || "\x0Ccanister-id")[:32]
|||
||| For now we represent as a list of bytes
public export
CmcSubaccount : Type
CmcSubaccount = List Bits8  -- 32 bytes

||| Calculate CMC subaccount for this canister
||| In reality this needs SHA256, here we provide the type signature
public export
calculateCmcSubaccount : List Bits8 -> CmcSubaccount
calculateCmcSubaccount canisterId =
  -- Placeholder: real implementation needs SHA256
  -- SHA256(canister_id ++ [0x0C] ++ "canister-id")
  replicate 32 0

-- =============================================================================
-- Exchange Rate Types
-- =============================================================================

||| DEX quote for ckETH → ICP swap
public export
record SwapQuote where
  constructor MkSwapQuote
  ||| Input amount (ckETH wei)
  inputAmount    : Integer
  ||| Output amount (ICP e8s)
  outputAmount   : Integer
  ||| Price impact (basis points, e.g., 50 = 0.5%)
  priceImpact    : Integer
  ||| Quote expiry timestamp
  expiresAt      : Integer

||| CMC exchange rate (ICP → Cycles)
||| Rate is in cycles per 10^8 e8s (1 ICP)
public export
record CmcRate where
  constructor MkCmcRate
  ||| Cycles per ICP (e.g., 1_000_000_000_000 = 1T cycles per ICP)
  cyclesPerIcp   : Integer
  ||| Timestamp of rate
  timestamp      : Integer

||| Default CMC rate (approximately 1T cycles per ICP)
public export
defaultCmcRate : CmcRate
defaultCmcRate = MkCmcRate 1_000_000_000_000 0

-- =============================================================================
-- Minting Operations
-- =============================================================================

||| Calculate cycles from ICP amount at given rate
public export
calculateCycles : CmcRate -> Integer -> Integer
calculateCycles rate icpE8s =
  (icpE8s * rate.cyclesPerIcp) `div` 100_000_000  -- divide by 1e8

||| Create a new minting request
public export
createMintingRequest :
  Integer ->       -- requestId
  Integer ->       -- ckEthAmount (wei)
  SwapQuote ->    -- DEX quote
  Integer ->       -- slippagePercent (e.g., 1 = 1%)
  Integer ->       -- currentTime
  MintingRequest
createMintingRequest reqId ckEth quote slippage now =
  let minIcp = (quote.outputAmount * (100 - slippage)) `div` 100
  in MkMintingRequest
       reqId
       ckEth
       quote.outputAmount
       minIcp
       MintingPending
       now
       now

||| Advance minting state machine
public export
advanceMintingState :
  MintingRequest ->
  MintingState ->
  Integer ->       -- currentTime
  MintingRequest
advanceMintingState req newState now =
  MkMintingRequest
    req.requestId
    req.ckEthAmount
    req.expectedIcp
    req.minIcp
    newState
    req.createdAt
    now

-- =============================================================================
-- Minting Registry
-- =============================================================================

||| Registry of all minting requests
public export
record MintingRegistry where
  constructor MkMintingRegistry
  ||| All requests
  requests       : List MintingRequest
  ||| Next request ID
  nextId         : Integer
  ||| Total cycles minted
  totalMinted    : Integer
  ||| Total ckETH converted
  totalConverted : Integer

||| Initial minting registry
public export
initialMintingRegistry : MintingRegistry
initialMintingRegistry = MkMintingRegistry [] 1 0 0

||| Find request by ID
public export
findMintingRequest : MintingRegistry -> Integer -> Maybe MintingRequest
findMintingRequest reg reqId =
  find (\r => r.requestId == reqId) reg.requests

||| Add new request to registry
public export
addMintingRequest : MintingRegistry -> MintingRequest -> MintingRegistry
addMintingRequest reg req =
  MkMintingRegistry
    (req :: reg.requests)
    (reg.nextId + 1)
    reg.totalMinted
    reg.totalConverted

||| Update request in registry
public export
updateMintingRequest : MintingRegistry -> MintingRequest -> MintingRegistry
updateMintingRequest reg req =
  let others = filter (\r => r.requestId /= req.requestId) reg.requests
      -- Update totals if completed
      (newMinted, newConverted) = case req.state of
        MintingCompleted cycles =>
          (reg.totalMinted + cycles, reg.totalConverted + req.ckEthAmount)
        _ => (reg.totalMinted, reg.totalConverted)
  in MkMintingRegistry
       (req :: others)
       reg.nextId
       newMinted
       newConverted

||| Get pending requests
public export
getPendingRequests : MintingRegistry -> List MintingRequest
getPendingRequests reg =
  filter isPending reg.requests
  where
    isPending : MintingRequest -> Bool
    isPending r = case r.state of
      MintingPending => True
      SwapInitiated _ => True
      SwapCompleted _ _ => True
      TransferToSubaccount _ => True
      NotifyingCMC _ => True
      _ => False

-- =============================================================================
-- Candid Method Names
-- =============================================================================

||| ICRC-2 approve method
public export
METHOD_ICRC2_APPROVE : String
METHOD_ICRC2_APPROVE = "icrc2_approve"

||| DEX swap method (varies by DEX)
public export
METHOD_SWAP : String
METHOD_SWAP = "swap"

||| CMC notify_top_up method
public export
METHOD_NOTIFY_TOP_UP : String
METHOD_NOTIFY_TOP_UP = "notify_top_up"

||| CMC get_icp_xdr_conversion_rate method
public export
METHOD_GET_CONVERSION_RATE : String
METHOD_GET_CONVERSION_RATE = "get_icp_xdr_conversion_rate"
