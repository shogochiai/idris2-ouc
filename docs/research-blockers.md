# Research Blockers: idris2-ouc → IC Deployment

## Status: Building ✅ | Deploying ❌

Successfully built 18/18 modules. Deployment requires solving these research questions.

## Research Tree

```
idris2-ouc IC Deployment
│
├── 1. Canister Entry Points [CRITICAL]
│   │
│   ├── 1.1 How to wire OUC business logic to canister exports?
│   │   ├── Q: idris2-wasm uses hardcoded C entry points (canister_entry.c)
│   │   ├── Q: OUC needs dynamic dispatch to multiple query/update methods
│   │   └── Q: How to call Idris2 functions from C entry points?
│   │
│   ├── 1.2 Method registration pattern?
│   │   ├── Q: One C entry per Candid method? (submitProposal, getProposal, etc.)
│   │   ├── Q: Or single dispatcher that routes by method name?
│   │   └── Q: How does idris2-cdk ICP.API expect methods to be structured?
│   │
│   └── 1.3 Main expression integration?
│       ├── Q: idris2-wasm calls __mainExpression_0() on init
│       ├── Q: OUC needs to initialize state (empty proposals, empty auditors)
│       └── Q: How to make Main.idr return initial OUCState?
│
├── 2. RefC Backend Scaling [HIGH]
│   │
│   ├── 2.1 Does RefC handle 18 modules with complex types?
│   │   ├── Q: idris2-wasm tested with trivial Main.idr (just prints)
│   │   ├── Q: OUC has dependent types, records, sum types
│   │   └── Q: Will generated C code compile with emscripten?
│   │
│   ├── 2.2 Memory model compatibility?
│   │   ├── Q: RefC uses reference counting
│   │   ├── Q: IC WASM has limited linear memory
│   │   └── Q: How to handle large state (many proposals, auditors)?
│   │
│   └── 2.3 Runtime dependencies?
│       ├── Q: Which RefC runtime functions are used by OUC?
│       ├── Q: Any unsupported libc functions needed?
│       └── Q: mini-gmp sufficient for OUC's Nat/Integer usage?
│
├── 3. Candid Serialization [HIGH]
│   │
│   ├── 3.1 How to encode/decode Candid in Idris2?
│   │   ├── Q: idris2-cdk has ICP.Candid.Types with Candidable typeclass
│   │   ├── Q: But idris2-wasm returns raw bytes, not Candid
│   │   └── Q: Who implements Candid binary encoding?
│   │
│   ├── 3.2 Type mapping?
│   │   ├── Q: Idris2 FR a ↔ Candid variant?
│   │   ├── Q: Idris2 Evidence ↔ Candid record?
│   │   └── Q: Idris2 Principal (from idris2-cdk) ↔ Candid principal?
│   │
│   └── 3.3 Message argument parsing?
│       ├── Q: How to read ic0.msg_arg_data in Idris2?
│       ├── Q: How to decode Candid args into Idris2 types?
│       └── Q: idris2-cdk ICP.IC0 has msg_arg_data_copy - how to use?
│
├── 4. IC0 System API Integration [MEDIUM]
│   │
│   ├── 4.1 Which IC0 calls does OUC need?
│   │   ├── ✅ msg_reply, msg_reply_data_append (basic responses)
│   │   ├── ❓ msg_arg_data_size, msg_arg_data_copy (read inputs)
│   │   ├── ❓ caller (authentication)
│   │   ├── ❓ time (timestamps)
│   │   ├── ❓ stable_* (state persistence)
│   │   └── ❓ call_* (inter-canister calls for HTTP outcall)
│   │
│   ├── 4.2 How to call IC0 from Idris2?
│   │   ├── Q: idris2-cdk ICP.IC0 has %foreign declarations
│   │   ├── Q: But foreign calls → C FFI → ic0 imports?
│   │   └── Q: RefC foreign call mechanism with WASM imports?
│   │
│   └── 4.3 HTTP outcall flow?
│       ├── Q: OUC HttpOutcall module uses management canister
│       ├── Q: Requires ic0.call_* for inter-canister calls
│       └── Q: Async pattern: call_new → call_data_append → call_perform
│
├── 5. State Persistence [MEDIUM]
│   │
│   ├── 5.1 Stable memory strategy?
│   │   ├── Q: OUCState contains proposals (SortedMap), auditors (List)
│   │   ├── Q: How to serialize to stable memory on upgrade?
│   │   ├── Q: idris2-cdk has ICP.StableMemory with Storable typeclass
│   │   └── Q: Who implements Storable for OUC types?
│   │
│   ├── 5.2 Pre/post upgrade hooks?
│   │   ├── Q: canister_pre_upgrade / canister_post_upgrade exports
│   │   └── Q: How to trigger Idris2 serialization from C entry?
│   │
│   └── 5.3 Memory limits?
│       ├── Q: IC stable memory: 96GB max
│       ├── Q: IC heap memory: 4GB max
│       └── Q: How to handle large proposal history?
│
└── 6. Build Pipeline [LOW]
    │
    ├── 6.1 How to extend build-canister.sh for OUC?
    │   ├── Q: OUC has 18 modules vs idris2-wasm's single Main.idr
    │   ├── Q: pack build generates .ttc files, not C
    │   └── Q: Need: idris2 --codegen refc with all dependencies
    │
    ├── 6.2 Dependency inclusion?
    │   ├── Q: idris2-cdk modules need to be in RefC output
    │   ├── Q: contrib (Data.Buffer, etc.) needs RefC support
    │   └── Q: How to compile entire dependency tree to C?
    │
    └── 6.3 WASI stubbing for complex builds?
        ├── Q: More WASI imports may appear with larger codebase
        └── Q: stub-wasi.sh may need extension
```

## Recommended Investigation Order

### Phase 1: Minimal Viable Canister (MVC)
1. **1.1** Create canister_entry.c for OUC with one method (getProposal)
2. **2.1** Test RefC compilation of single OUC module
3. **6.1** Extend build script for multi-module project

### Phase 2: Input/Output
4. **3.1** Implement Candid encoding for FR type
5. **4.2** Verify IC0 calls work from Idris2 via RefC
6. **3.3** Parse incoming Candid arguments

### Phase 3: Full Functionality
7. **4.1** Add all needed IC0 calls
8. **5.1** Implement state serialization
9. **4.3** HTTP outcall integration

## Key Unknowns

| # | Unknown | Risk | Mitigation |
|---|---------|------|------------|
| 1 | RefC + dependent types | High | Test with simplified OUC subset |
| 2 | Candid binary encoding | High | May need C library or manual impl |
| 3 | IC0 FFI from RefC | Medium | Test with idris2-cdk examples |
| 4 | Multi-module RefC build | Medium | Examine idris2 --codegen refc output |

## References

- [idris2-wasm canister_entry.c](../../../idris2-wasm/lib/ic0/canister_entry.c) - Working entry point pattern
- [idris2-wasm build-canister.sh](../../../idris2-wasm/scripts/build-canister.sh) - Working build pipeline
- [idris2-cdk ICP.IC0](../../../idris2-cdk/src/ICP/IC0.idr) - IC0 FFI declarations
- [IC Interface Spec](https://internetcomputer.org/docs/current/references/ic-interface-spec) - Official IC0 API
