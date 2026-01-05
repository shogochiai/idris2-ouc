# OptimisticUpgraderCanister (OUC)

An ICP canister written in Idris2 that coordinates optimistic upgrades for EVM smart contracts using the ERC-7546 proxy pattern.

## Overview

The OUC serves as a cross-chain orchestrator that:

- Receives upgrade proposals for EVM contracts
- Manages auditor pool and VRF-based assignment
- Collects n-of-n multisig approvals
- Authorizes execution via threshold signatures (vetKeys)
- Records evidence for all operations (FRC compliance)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                    ICP (Internet Computer)                          │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │               OptimisticUpgraderCanister (OUC)               │   │
│  │  ┌─────────────┬───────────────┬─────────────┬────────────┐  │   │
│  │  │  Proposals  │  AuditorPool  │   Rewards   │  MultiSig  │  │   │
│  │  └─────────────┴───────────────┴─────────────┴────────────┘  │   │
│  │                           │                                  │   │
│  │                    FRC.Core (Evidence)                       │   │
│  └──────────────────────────│───────────────────────────────────┘   │
│                             │ HTTP Outcall                          │
└─────────────────────────────│───────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         EVM Chain                                   │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  OptimisticUpgrader (OU)  ──▶  ERC-7546 Proxy  ──▶  Impl    │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Theoretical Foundation

This project implements two formal theories:

### Failure-Recovery Calculus (FRC)

All operations return `FR a` (Failure-Recovery result):
- **Classified failures**: No "Unknown" - every failure has a type
- **Evidence-carrying**: Every result includes diagnostic context
- **Recovery closure**: Failures are handled at explicit boundaries

See [docs/FRC.pdf](docs/FRC.pdf) for the formal treatment.

### AGA Loop (Ask-Gap-Action)

Development follows the AGA methodology:
- **Ask**: Inspect current state via `lazy core ask`
- **Gap**: Identify STI (Spec-Test-Implementation) violations
- **Action**: Execute recommended fixes

See [docs/AGA Loop.pdf](docs/AGA%20Loop.pdf) for details.

## Project Structure

```
src/
├── FRC/
│   └── Core.idr           # Failure-Recovery types (FR, IcpFail, Evidence)
├── OUC/
│   ├── Core.idr           # State, proposals, auditors
│   ├── MultiSig.idr       # Voting sessions, signature aggregation
│   ├── Signatures.idr     # Signature validation
│   └── Relay.idr          # Cross-chain relay logic
├── AuditorPool/
│   └── Core.idr           # Auditor registration, reputation
├── Rewards/
│   └── Core.idr           # Reward distribution
├── Proposals/
│   └── Core.idr           # Proposal lifecycle
├── ERC7546/
│   ├── Dictionary.idr     # ERC-7546 dictionary operations
│   └── Upgrade.idr        # Upgrade execution flow
├── HttpOutcall/
│   ├── Core.idr           # HTTP outcall abstractions
│   ├── EvmRpc.idr         # EVM JSON-RPC client
│   └── TxSender/          # Transaction building & sending
└── Util/
    ├── StringHex.idr      # Hex encoding utilities
    └── StringCase.idr     # String case conversion
```

## Building

### Remote Build (Recommended)

Building Idris2 requires significant RAM. Use the remote build script:

```bash
./scripts/remote-build.sh
```

This script:
1. Spins up a Hetzner CCX33 (32GB RAM)
2. Installs Idris2 + idris2-cdk
3. Builds the project
4. Downloads artifacts to `build/`
5. Terminates the server

### Local Build

Requires:
- Idris2 with Chez Scheme backend
- [idris2-cdk](https://github.com/shogochiai/idris2-cdk) installed

```bash
idris2 --build ouc.ipkg
```

### Deploy to ICP

```bash
dfx deploy --network ic
```

## Development Workflow

Use `lazy core ask` to analyze and guide development:

```bash
# Full analysis
lazy core ask src/

# Phase 1 (Vibe Bootstrap): Test discovery
lazy core ask src/ --steps=4

# Phase 2 (Spec Emergence): STI parity
lazy core ask src/ --steps=1,2,3

# Phase 3 (TDVC): Type-driven refinement
lazy core ask src/ --steps=3,5
```

## Key Types

### FR (Failure-Recovery)

```idris
data FR : Type -> Type where
  Ok   : (value : a) -> (evidence : Evidence) -> FR a
  Fail : (failure : IcpFail) -> (evidence : Evidence) -> FR a
```

### Proposal Lifecycle

```
Pending → UnderReview → Approved → Executed
                     ↘ Rejected
                     ↘ Expired
                     ↘ Cancelled
```

### IcpFail (Failure Surface)

Closed sum type - no "Unknown" failures:
- `Trap`, `Reject`, `SysInvariant`
- `DecodeError`, `EncodeError`, `StableMemError`
- `CallError`, `Unauthorized`, `Conflict`
- `NotFound`, `InvalidState`, `RateLimited`
- `Timeout`, `Internal`

## Candid Interface

See [can.did](can.did) for the complete interface. Key methods:

| Method | Type | Description |
|--------|------|-------------|
| `submitProposal` | update | Submit upgrade proposal |
| `registerAuditor` | update | Join auditor pool |
| `submitReview` | update | Submit auditor review |
| `prepareExecution` | update | Prepare execution request |
| `recordExecution` | update | Record EVM execution result |
| `getProposal` | query | Fetch proposal by ID |
| `getActiveAuditors` | query | List active auditors |

## Dependencies

- [idris2-cdk](https://github.com/shogochiai/idris2-cdk) - ICP canister development kit for Idris2
- [idris2-wasm](https://github.com/shogochiai/idris2-wasm) - Reference implementation for Idris2→WASM→IC pipeline

### Stack

```
┌─────────────────────────────────────────────────────────────┐
│                      idris2-ouc (this project)              │
│               (OptimisticUpgraderCanister)                  │
└─────────────────────────────────────────────────────────────┘
                            │ uses
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      idris2-cdk                             │
│   ICP.IC0 │ ICP.API │ ICP.Candid │ ICP.StableMemory        │
└─────────────────────────────────────────────────────────────┘
                            │ built on
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      idris2-wasm                            │
│   Idris2 → RefC → Emscripten → WASM → WASI stub → IC       │
└─────────────────────────────────────────────────────────────┘
```

## License

TBD
