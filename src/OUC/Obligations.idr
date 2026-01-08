||| Graded Monad for Obligation Tracking
|||
||| Provides type-level tracking of computational obligations:
||| - HTTP outcalls (to EVM RPC endpoints)
||| - Cycles consumption
||| - State modifications
||| - External canister calls
|||
||| Based on Karma.Graded pattern for ICP obligation tracking.
|||
||| Usage:
|||   -- Type signature shows all obligations
|||   sendTx : OFR [HttpCall "evm-rpc", CyclesConsumed 10000000000, StateModified] TxHash
module OUC.Obligations

import public FRMonad.Graded
import public FRMonad.Failure
import public FRMonad.Evidence
import OUC.Core
import HttpOutcall.Core
import Data.List

%default total

-- =============================================================================
-- OUC-Specific Obligation Aliases
-- =============================================================================

||| HTTP call to EVM RPC endpoint
public export
EvmRpcCall : String -> Obligation
EvmRpcCall endpoint = HttpCall endpoint

||| HTTP call to any external API
public export
ExternalHttpCall : String -> Obligation
ExternalHttpCall = HttpCall

||| Inter-canister call obligation
public export
CanisterCall : String -> Obligation
CanisterCall = ExternalCall

||| Cycles for HTTP outcall
public export
HttpOutcallCycles : Nat
HttpOutcallCycles = 100000000000  -- 100B cycles default

-- =============================================================================
-- OFR: OUC Failure-Recovery Graded Monad
-- =============================================================================

||| Type alias for OUC operations with obligation tracking
||| This is just GFR specialized for OUC context
public export
OFR : Obligations -> Type -> Type
OFR = GFR

-- =============================================================================
-- OUC-Specific Operations
-- =============================================================================

||| Record EVM RPC call obligation
public export
oevmRpcCall : (endpoint : String) -> OFR [HttpCall endpoint] ()
oevmRpcCall = ghttpCall

||| Record cycles consumption for HTTP outcall
public export
ohttpCycles : OFR [CyclesConsumed HttpOutcallCycles] ()
ohttpCycles = gconsumeCycles HttpOutcallCycles

||| Record canister call obligation
public export
ocanisterCall : (target : String) -> OFR [ExternalCall target] ()
ocanisterCall = gexternalCall

||| Record state modification
public export
ostateModified : OFR [StateModified] ()
ostateModified = gmodifyState

-- =============================================================================
-- EVM Transaction Operations - Obligation Type Declarations
-- =============================================================================

||| EVM transaction send obligations
||| Includes: RPC call + signing cycles + state update
public export
EvmTxObligations : String -> Obligations
EvmTxObligations rpcEndpoint =
  [ HttpCall rpcEndpoint
  , CyclesConsumed HttpOutcallCycles
  , StateModified
  ]

||| EVM transaction confirmation polling obligations
||| Multiple RPC calls for confirmation
public export
EvmConfirmObligations : String -> Nat -> Obligations
EvmConfirmObligations rpcEndpoint pollCount =
  replicate pollCount (HttpCall rpcEndpoint) ++
  [CyclesConsumed (HttpOutcallCycles * pollCount)]

-- =============================================================================
-- Upgrade Execution Obligations
-- =============================================================================

||| Obligations for full upgrade execution
||| - RPC call to send tx
||| - RPC calls to confirm (estimated)
||| - State modification to record result
||| - Cycles for all operations
public export
UpgradeExecObligations : String -> Obligations
UpgradeExecObligations rpcEndpoint =
  [ HttpCall rpcEndpoint              -- eth_sendRawTransaction
  , HttpCall rpcEndpoint              -- eth_getTransactionReceipt (poll 1)
  , HttpCall rpcEndpoint              -- eth_getTransactionReceipt (poll 2)
  , CyclesConsumed (HttpOutcallCycles * 3)
  , StateModified                     -- Record result
  ]

-- =============================================================================
-- Multi-Chain Operations
-- =============================================================================

||| Cross-chain upgrade obligations
||| One call per chain
public export
MultiChainObligations : List String -> Obligations
MultiChainObligations endpoints =
  concatMap (\e => [HttpCall e, CyclesConsumed HttpOutcallCycles]) endpoints
  ++ [StateModified]

-- =============================================================================
-- Obligation Analysis (using re-exported functions from FRMonad.Graded)
-- =============================================================================

||| Estimate total cycles from obligations
public export
estimateCycles : Obligations -> Nat
estimateCycles = totalCyclesConsumed

||| Check if obligations include state modification
public export
modifiesState : Obligations -> Bool
modifiesState = hasStateModifiedObligation

||| Check if operation is read-only (no state modification)
public export
isReadOnly : Obligations -> Bool
isReadOnly obs = not (modifiesState obs)

-- =============================================================================
-- Obligation Validation
-- =============================================================================

||| Validate sufficient cycles for obligations
public export
ovalidateCycles : (available : Nat) -> (required : Nat) -> OFR [] ()
ovalidateCycles available required =
  gguard (available >= required)
         (InsufficientCycles required ("Need " ++ show required ++ " but have " ++ show available))

||| Validate obligations against canister limits
public export
ovalidateObligations : Obligations -> Nat -> OFR [] ()
ovalidateObligations obs maxCycles =
  let required = estimateCycles obs
      httpCount = FRMonad.Graded.countHttpCalls obs
  in if required > maxCycles
       then GFail (InsufficientCycles required ("Obligations require " ++ show required ++ " cycles"))
                  (mkEvidence Update "validateObligations" "Cycles exceeded")
       else if httpCount > 100
              then GFail (ValidationError $ "Too many HTTP calls: " ++ show httpCount)
                         (mkEvidence Update "validateObligations" "HTTP calls exceeded")
              else gpure ()

-- =============================================================================
-- Type-level Obligation Proofs
-- =============================================================================

-- The type system ensures:
--
-- 1. Obligation visibility:
--    upgrade : OFR [HttpCall "rpc", CyclesConsumed 100B, StateModified] ()
--    ^ All effects visible in type signature
--
-- 2. Obligation accumulation:
--    sendAndConfirm : OFR (EvmTxObligations rpc ++ EvmConfirmObligations rpc 3) ()
--    ^ Composed operations accumulate obligations
--
-- 3. Query safety:
--    pureQuery : OFR [] Result  -- guaranteed no side effects
--    ^ Can enforce read-only at type level
--
-- 4. Cycles estimation at compile time:
--    The type EvmTxObligations "rpc" tells us exactly what cycles are needed

-- =============================================================================
-- Example Signatures
-- =============================================================================

-- Example: Read-only query (no obligations)
-- getProposalStatus : ProposalId -> OFR [] ProposalStatus

-- Example: State-modifying update
-- submitProposal : UpgradeProposal -> OFR [StateModified] ProposalId

-- Example: Full upgrade flow with explicit obligations
-- executeUpgrade : UpgradeExecParams -> OFR (UpgradeExecObligations "https://rpc.eth") TxHash

-- Example: Multi-step with accumulated obligations
-- fullFlow : OFR [StateModified, HttpCall "rpc1", HttpCall "rpc2", CyclesConsumed 200B] ()

-- =============================================================================
-- Note: Composite operations that sequence multiple obligation types
-- require an accumulating bind implementation. For now, use the type
-- signatures above to document obligations, and implement the actual
-- operations when a proper accumulating graded monad is available.
-- =============================================================================
