import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface _SERVICE {
  'assignAuditor' : ActorMethod<[bigint, Principal], string>,
  'cancelProposal' : ActorMethod<[bigint], string>,
  'distributeReward' : ActorMethod<[Principal, bigint], string>,
  /**
   * A-Life Economics
   */
  'donate' : ActorMethod<[string], string>,
  'getActiveAuditors' : ActorMethod<[], string>,
  'getAuditor' : ActorMethod<[Principal], string>,
  'getAuditorCount' : ActorMethod<[], bigint>,
  'getOwner' : ActorMethod<[], string>,
  'getPendingReward' : ActorMethod<[Principal], bigint>,
  /**
   * Query Methods
   */
  'getProposal' : ActorMethod<[bigint], string>,
  'getProposalCount' : ActorMethod<[], bigint>,
  'getProposalsByChain' : ActorMethod<[bigint], string>,
  'getProposalsByStatus' : ActorMethod<[string], string>,
  'getProtocolBalance' : ActorMethod<[string], bigint>,
  'getProtocolCount' : ActorMethod<[], bigint>,
  'getProtocolTier' : ActorMethod<[string], bigint>,
  'getReviewsForProposal' : ActorMethod<[bigint], string>,
  'getTotalDistributed' : ActorMethod<[Principal], bigint>,
  'getTreasuryBalance' : ActorMethod<[], bigint>,
  'getVersion' : ActorMethod<[], bigint>,
  'prepareExecution' : ActorMethod<[bigint], string>,
  'reactivateAuditor' : ActorMethod<[], string>,
  'recordExecution' : ActorMethod<[bigint, string], string>,
  'registerAuditor' : ActorMethod<[], string>,
  /**
   * Update Methods
   * MVP: registerAuditor/suspendAuditor/reactivateAuditor ignore arguments
   * Full Candid arg parsing will be added in Phase 3
   */
  'submitProposal' : ActorMethod<[string], string>,
  'submitReview' : ActorMethod<[bigint, string], string>,
  'suspendAuditor' : ActorMethod<[], string>,
  /**
   * HTTP Outcall Test
   */
  'testEthBlockNumber' : ActorMethod<[], string>,
  'testEvmRpc' : ActorMethod<[], string>,
  'transferOwnership' : ActorMethod<[Principal], string>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
