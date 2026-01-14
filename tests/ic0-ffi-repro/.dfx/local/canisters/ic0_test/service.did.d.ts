import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

/**
 * IC0 FFI Bug #3 Test Canister Interface
 */
export interface _SERVICE {
  /**
   * C wrapper call to ic0_time (bypasses only Idris2)
   */
  'test_c_wrapper' : ActorMethod<[], bigint>,
  /**
   * Direct C call to ic0_time_impl (bypasses Idris2 and C wrapper)
   */
  'test_direct' : ActorMethod<[], bigint>,
  /**
   * Run FFI test and return the time value captured via Idris2 FFI
   * If Bug #3 is present, this returns 0
   * If working correctly, this returns non-zero nanoseconds
   */
  'test_ffi' : ActorMethod<[], bigint>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
