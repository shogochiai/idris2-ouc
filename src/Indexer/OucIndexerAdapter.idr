||| OUC Indexer Adapter
|||
||| Integrates idris2-icp-indexer library with OUC-specific event types.
||| Dashboard calls OUC → OUC uses this adapter → Indexer library
module Indexer.OucIndexerAdapter

import Core as Indexer
import Storage as IndexerStorage
import Query as IndexerQuery
import Data.List

import OUC.Types.Validated.Address
import OUC.Types.Validated.Proposal
import OUC.Types.Validated.Chain

%default total

-- =============================================================================
-- OUC Event Signatures (keccak256 of event signatures)
-- =============================================================================

||| UpgradeProposed(uint256 proposalId, address target, address newImpl, address ou)
public export
upgradeProposedTopic : Indexer.Bytes32
upgradeProposedTopic = MkBytes32 "0x76d0906e8e4c8e9c0d9f8c8d8f8e8d8c8b8a8988878685848382818079787776"

||| VoteCast(uint256 proposalId, address auditor, bool approve)
public export
voteCastTopic : Indexer.Bytes32
voteCastTopic = MkBytes32 "0x877e8e9e8d8c8b8a89888786858483828180797877767574737271706f6e6d6c"

||| ProposalExecuted(uint256 proposalId, address executor)
public export
proposalExecutedTopic : Indexer.Bytes32
proposalExecutedTopic = MkBytes32 "0x989a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8"

||| AuditorRegistered(address auditor, string name)
public export
auditorRegisteredTopic : Indexer.Bytes32
auditorRegisteredTopic = MkBytes32 "0xabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9ca"

||| AuditorSuspended(address auditor)
public export
auditorSuspendedTopic : Indexer.Bytes32
auditorSuspendedTopic = MkBytes32 "0xcbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9ea"

||| All OUC-relevant event signatures
public export
oucEventTopics : List Indexer.Bytes32
oucEventTopics =
  [ upgradeProposedTopic
  , voteCastTopic
  , proposalExecutedTopic
  , auditorRegisteredTopic
  , auditorSuspendedTopic
  ]

-- =============================================================================
-- OUC-Specific Event Types
-- =============================================================================

||| Parsed OUC event
public export
data OucEvent
  = UpgradeProposed Nat String String String  -- proposalId, target, newImpl, ou
  | VoteCast Nat String Bool                  -- proposalId, auditor, approve
  | ProposalExecuted Nat String               -- proposalId, executor
  | AuditorRegistered String String           -- auditor, name
  | AuditorSuspended String                   -- auditor
  | UnknownEvent Indexer.IndexedEvent         -- Fallback

public export
Show OucEvent where
  show (UpgradeProposed pid target impl ou) =
    "UpgradeProposed(id=" ++ show pid ++ ", target=" ++ target ++ ")"
  show (VoteCast pid auditor approve) =
    "VoteCast(id=" ++ show pid ++ ", auditor=" ++ auditor ++ ", approve=" ++ show approve ++ ")"
  show (ProposalExecuted pid executor) =
    "ProposalExecuted(id=" ++ show pid ++ ", executor=" ++ executor ++ ")"
  show (AuditorRegistered auditor name) =
    "AuditorRegistered(auditor=" ++ auditor ++ ", name=" ++ name ++ ")"
  show (AuditorSuspended auditor) =
    "AuditorSuspended(auditor=" ++ auditor ++ ")"
  show (UnknownEvent e) =
    "UnknownEvent(" ++ show e ++ ")"

-- =============================================================================
-- Event Parsing
-- =============================================================================

||| Parse IndexedEvent into OUC domain event
||| TODO: Implement actual ABI decoding
public export
parseOucEvent : Indexer.IndexedEvent -> OucEvent
parseOucEvent event =
  if event.topic0 == upgradeProposedTopic
     then UpgradeProposed 0 "" "" ""  -- TODO: decode from data_
  else if event.topic0 == voteCastTopic
     then VoteCast 0 "" False         -- TODO: decode from data_
  else if event.topic0 == proposalExecutedTopic
     then ProposalExecuted 0 ""       -- TODO: decode from data_
  else if event.topic0 == auditorRegisteredTopic
     then AuditorRegistered "" ""     -- TODO: decode from data_
  else if event.topic0 == auditorSuspendedTopic
     then AuditorSuspended ""         -- TODO: decode from data_
  else UnknownEvent event

-- =============================================================================
-- OUC Contract Configuration
-- =============================================================================

||| Create contract config for an OU (Optimistic Upgrader) on a chain
public export
mkOuContractConfig : Indexer.ChainId -> String -> Nat -> String -> Indexer.ContractConfig
mkOuContractConfig chainId ouAddress fromBlock label =
  MkContractConfig
    chainId
    (MkEvmAddress ouAddress)
    oucEventTopics
    fromBlock
    label

||| Ethereum mainnet OU config (example)
public export
ethereumOuConfig : String -> Nat -> Indexer.ContractConfig
ethereumOuConfig ouAddr fromBlock =
  mkOuContractConfig Indexer.ethereumMainnet ouAddr fromBlock "OU-Ethereum"

||| Arbitrum OU config (example)
public export
arbitrumOuConfig : String -> Nat -> Indexer.ContractConfig
arbitrumOuConfig ouAddr fromBlock =
  mkOuContractConfig Indexer.arbitrumOne ouAddr fromBlock "OU-Arbitrum"

||| Base mainnet OU config (example)
public export
baseOuConfig : String -> Nat -> Indexer.ContractConfig
baseOuConfig ouAddr fromBlock =
  mkOuContractConfig Indexer.baseMainnet ouAddr fromBlock "OU-Base"

-- =============================================================================
-- OUC Query Interface
-- =============================================================================

||| Get all UpgradeProposed events for an OU address
public export
getUpgradeProposedEvents : IndexerStorage.IndexerState -> String -> List Indexer.IndexedEvent
getUpgradeProposedEvents state ouAddr =
  let addrFilter = { address := Just (MkEvmAddress ouAddr)
                   , topic0 := Just upgradeProposedTopic } Indexer.emptyFilter
  in IndexerStorage.queryEvents state addrFilter

||| Get all VoteCast events for a proposal
public export
getVotesForProposal : IndexerStorage.IndexerState -> Nat -> List Indexer.IndexedEvent
getVotesForProposal state proposalId =
  let topicFilter = { topic0 := Just voteCastTopic } Indexer.emptyFilter
      -- TODO: filter by proposalId in topic1 or data
  in IndexerStorage.queryEvents state topicFilter

||| Get proposal execution event
public export
getProposalExecution : IndexerStorage.IndexerState -> Nat -> Maybe Indexer.IndexedEvent
getProposalExecution state proposalId =
  let topicFilter = { topic0 := Just proposalExecutedTopic } Indexer.emptyFilter
      events = IndexerStorage.queryEvents state topicFilter
      -- TODO: filter by proposalId
  in head' events

||| Get auditor registration events
public export
getAuditorRegistrations : IndexerStorage.IndexerState -> List Indexer.IndexedEvent
getAuditorRegistrations state =
  let topicFilter = { topic0 := Just auditorRegisteredTopic } Indexer.emptyFilter
  in IndexerStorage.queryEvents state topicFilter

||| Get recent OUC events (all types) for dashboard
public export
getRecentOucEvents : IndexerStorage.IndexerState -> Nat -> List (Indexer.IndexedEvent, OucEvent)
getRecentOucEvents state limit =
  let allEvents = take limit state.events
      oucEvents = filter (\e => elem e.topic0 oucEventTopics) allEvents
  in map (\e => (e, parseOucEvent e)) oucEvents

-- =============================================================================
-- Dashboard Data Aggregation
-- =============================================================================

||| Dashboard summary for an OU
public export
record OuDashboardSummary where
  constructor MkOuDashboardSummary
  chainId           : Nat
  ouAddress         : String
  totalProposals    : Nat
  pendingProposals  : Nat
  executedProposals : Nat
  recentEvents      : List OucEvent
  lastSyncBlock     : Nat

||| Build dashboard summary for an OU
public export
buildOuSummary : IndexerStorage.IndexerState -> Indexer.ChainId -> String -> OuDashboardSummary
buildOuSummary state chainId ouAddr =
  let proposals = getUpgradeProposedEvents state ouAddr
      executions = IndexerStorage.queryEvents state ({ topic0 := Just proposalExecutedTopic } Indexer.emptyFilter)
      recent = map snd (getRecentOucEvents state 10)
      -- TODO: get cursor for lastSyncBlock
  in MkOuDashboardSummary
       chainId.value
       ouAddr
       (length proposals)
       0  -- TODO: count pending
       (length executions)
       recent
       0  -- TODO: from cursor

||| Aggregate summaries for all registered OUs
public export
buildAllOuSummaries : IndexerStorage.IndexerState -> List (Indexer.ChainId, String) -> List OuDashboardSummary
buildAllOuSummaries state ous = map (\(cid, addr) => buildOuSummary state cid addr) ous
