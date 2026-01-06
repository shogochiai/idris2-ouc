||| OUC Canister Main Entry Point
|||
||| This module provides the main expression that initializes the canister.
||| The C entry points in canister_entry.c call __mainExpression_0()
||| which executes this main function.
module Main

import OUC.Core
import FRC.Core

%default total

||| Initialize OUC state with anonymous principal (will be set properly in canister_init)
export
initialOUCState : OUCState
initialOUCState = initialState (MkICPrincipal "aaaaa-aa")

||| Main expression - called by canister_init
||| For now, just returns unit. The actual state is managed in C until
||| we implement proper FFI state passing.
main : IO ()
main = pure ()
