# Threshold ECDSA Integration Design

## ICP Chain-Key Signatures for EVM Transaction Signing

---

## 1. Overview

OUC uses ICP's Threshold ECDSA (t-ECDSA) to sign EVM transactions without any single party holding the private key.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Threshold ECDSA Architecture                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐     ┌───────────────┐     ┌───────────────┐             │
│  │  OUC Canister │────▶│  Management   │────▶│  t-ECDSA      │             │
│  │               │     │  Canister     │     │  Subnet       │             │
│  │  (caller)     │     │  (aaaaa-aa)   │     │  (34 nodes)   │             │
│  └───────────────┘     └───────────────┘     └───────────────┘             │
│         │                                           │                       │
│         │ sign_with_ecdsa                          │                       │
│         │ ecdsa_public_key                         │                       │
│         │                                           │                       │
│         ▼                                           ▼                       │
│  ┌───────────────┐                          ┌───────────────┐             │
│  │  Upgrade      │                          │  Signature    │             │
│  │  Calldata     │                          │  (r, s, v)    │             │
│  └───────────────┘                          └───────────────┘             │
│                                                     │                       │
│                                                     ▼                       │
│                                              ┌───────────────┐             │
│                                              │  EVM Chain    │             │
│                                              │  Transaction  │             │
│                                              └───────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. API Reference

### 2.1 Candid Types

```candid
// Curve type
type ecdsa_curve = variant { secp256k1 };

// Key identifier
type key_id = record {
  curve : ecdsa_curve;
  name : text;
};

// Sign request
type sign_with_ecdsa_args = record {
  message_hash : blob;       // 32-byte hash to sign
  derivation_path : vec blob; // Key derivation path
  key_id : key_id;
};

type sign_with_ecdsa_result = record {
  signature : blob;           // DER-encoded ECDSA signature
};

// Public key request
type ecdsa_public_key_args = record {
  canister_id : opt canister_id;
  derivation_path : vec blob;
  key_id : key_id;
};

type ecdsa_public_key_result = record {
  public_key : blob;          // SEC1-encoded public key
  chain_code : blob;          // For BIP-32 derivation
};
```

### 2.2 Key IDs

| Name | Environment | Subnet Size | Use Case |
|------|-------------|-------------|----------|
| `dfx_test_key` | Local only | N/A | Development |
| `test_key_1` | Mainnet | 13 nodes | Testing |
| `key_1` | Mainnet | 34 nodes (fiduciary) | Production |

### 2.3 Master Public Keys (secp256k1)

```
key_1:      02121bc3a5c38f38ca76487c72007ebbfd34bc6c4cb80a671655aa94585bbd0a02
test_key_1: 02f9ac345f6be6db51e1c5612cddb59e72c3d0d493c994d12035cf13257e3b1fa7
```

---

## 3. Idris2 Implementation

### 3.1 Types

```idris
-- ThresholdECDSA/Core.idr

||| ECDSA curve (currently only secp256k1)
public export
data EcdsaCurve = Secp256k1

||| Key identifier
public export
record KeyId where
  constructor MkKeyId
  curve : EcdsaCurve
  name  : String

||| Production key
export
productionKey : KeyId
productionKey = MkKeyId Secp256k1 "key_1"

||| Test key (mainnet)
export
testKey : KeyId
testKey = MkKeyId Secp256k1 "test_key_1"

||| Local dev key
export
localKey : KeyId
localKey = MkKeyId Secp256k1 "dfx_test_key"

||| Derivation path for chain-specific keys
||| Following BIP-44: m/44'/60'/0'/0/{chainId}
public export
record DerivationPath where
  constructor MkDerivationPath
  segments : List (List Bits8)

||| Build derivation path for EVM chain
export
evmDerivationPath : Nat -> DerivationPath
evmDerivationPath chainId =
  MkDerivationPath
    [ [0x00, 0x00, 0x00, 0x2C]   -- 44' (purpose)
    , [0x00, 0x00, 0x00, 0x3C]   -- 60' (coin type: ETH)
    , [0x00, 0x00, 0x00, 0x00]   -- 0'  (account)
    , [0x00, 0x00, 0x00, 0x00]   -- 0   (change)
    , encodeNat32 chainId       -- chain ID as index
    ]
```

### 3.2 FFI Bindings

```idris
-- ThresholdECDSA/FFI.idr

||| Sign message hash with threshold ECDSA
||| Requires ~25B cycles for signature
export
%foreign "C:ouc_sign_with_ecdsa,libic0"
prim__signWithEcdsa :
  PrimIO Bits32  -- Returns 0 on success, error code otherwise

||| Get public key for derivation path
export
%foreign "C:ouc_ecdsa_public_key,libic0"
prim__ecdsaPublicKey :
  PrimIO Bits32

||| Set message hash for signing (32 bytes)
export
%foreign "C:ouc_set_message_hash,libic0"
prim__setMessageHash :
  Bits32 -> Bits32 -> Bits32 -> Bits32 ->
  Bits32 -> Bits32 -> Bits32 -> Bits32 ->
  PrimIO ()

||| Get signature result (64 bytes: r || s)
export
%foreign "C:ouc_get_signature,libic0"
prim__getSignature :
  Bits32 ->  -- buffer offset
  PrimIO ()
```

### 3.3 C Implementation

```c
// lib/ic0/threshold_ecdsa.c

#include <stdint.h>

// IC System API imports
extern int32_t ic0_call_new(
    int32_t callee_src, int32_t callee_size,
    int32_t method_src, int32_t method_size,
    int32_t reply_fun, int32_t reply_env,
    int32_t reject_fun, int32_t reject_env
);
extern void ic0_call_data_append(int32_t src, int32_t size);
extern void ic0_call_cycles_add128(int64_t low, int64_t high);
extern int32_t ic0_call_perform(void);

// Management canister ID: aaaaa-aa
static const uint8_t MANAGEMENT_CANISTER[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01};

// Storage for signing request/result
static uint8_t g_message_hash[32];
static uint8_t g_signature[64];
static uint8_t g_derivation_path[128];
static uint32_t g_derivation_path_len;

// Key configuration
static const char* g_key_name = "key_1";  // Production key

void ouc_set_message_hash(
    uint32_t h0, uint32_t h1, uint32_t h2, uint32_t h3,
    uint32_t h4, uint32_t h5, uint32_t h6, uint32_t h7
) {
    // Store 32-byte hash from 8 uint32s
    uint32_t* hash32 = (uint32_t*)g_message_hash;
    hash32[0] = h0; hash32[1] = h1; hash32[2] = h2; hash32[3] = h3;
    hash32[4] = h4; hash32[5] = h5; hash32[6] = h6; hash32[7] = h7;
}

// Candid encoding for sign_with_ecdsa
static uint32_t encode_sign_request(uint8_t* buf) {
    uint32_t pos = 0;

    // DIDL magic
    buf[pos++] = 'D'; buf[pos++] = 'I'; buf[pos++] = 'D'; buf[pos++] = 'L';

    // Type table (1 type: record)
    buf[pos++] = 0x01;  // 1 type
    buf[pos++] = 0x6C;  // record
    buf[pos++] = 0x03;  // 3 fields

    // Field: derivation_path (hash: 0x...)
    // Field: key_id (hash: 0x...)
    // Field: message_hash (hash: 0x...)
    // ... (full Candid encoding)

    return pos;
}

int32_t ouc_sign_with_ecdsa(void) {
    // Encode request
    uint8_t request[256];
    uint32_t request_len = encode_sign_request(request);

    // Call management canister
    ic0_call_new(
        (int32_t)MANAGEMENT_CANISTER, 10,
        (int32_t)"sign_with_ecdsa", 15,
        0, 0,  // reply callback (to be set)
        0, 0   // reject callback
    );

    // Append request data
    ic0_call_data_append((int32_t)request, request_len);

    // Attach cycles (25B for production key)
    ic0_call_cycles_add128(25000000000, 0);

    // Perform async call
    return ic0_call_perform();
}
```

---

## 4. EVM Transaction Signing

### 4.1 Transaction Hash

```idris
-- ThresholdECDSA/EvmTx.idr

||| EIP-1559 transaction for signing
public export
record Eip1559Tx where
  constructor MkEip1559Tx
  chainId        : Nat
  nonce          : Nat
  maxPriorityFee : Nat
  maxFee         : Nat
  gasLimit       : Nat
  to             : EvmAddress
  value          : Nat
  data           : List Bits8
  accessList     : List (EvmAddress, List Bits256)

||| Compute transaction hash for signing
||| Returns keccak256(0x02 || RLP([chainId, nonce, ...]))
export
computeTxHash : Eip1559Tx -> List Bits8
computeTxHash tx =
  let rlpEncoded = rlpEncode tx
      prefixed = 0x02 :: rlpEncoded
  in keccak256 prefixed

||| Sign EIP-1559 transaction
export
signTransaction :
  Eip1559Tx ->
  KeyId ->
  DerivationPath ->
  FR (List Bits8)  -- Returns signed tx bytes
signTransaction tx keyId path = do
  let txHash = computeTxHash tx
  sig <- signWithEcdsa keyId path txHash
  let (r, s, v) = decodeSignature sig tx.chainId
  pure $ encodeSignedTx tx r s v
```

### 4.2 Signature Recovery

```idris
-- ThresholdECDSA/Recovery.idr

||| Compute recovery ID (v) for EIP-155
||| v = chainId * 2 + 35 + recovery_bit
export
computeRecoveryId : Nat -> Bits8 -> Nat
computeRecoveryId chainId recoveryBit =
  chainId * 2 + 35 + cast recoveryBit

||| Decode DER signature to (r, s)
export
decodeDerSignature : List Bits8 -> Maybe (List Bits8, List Bits8)
decodeDerSignature der = do
  -- DER format: 0x30 len 0x02 rlen r 0x02 slen s
  guard $ length der >= 8
  guard $ index' 0 der == Just 0x30
  let rLen = cast $ fromMaybe 0 $ index' 3 der
  let r = take rLen $ drop 4 der
  let sLen = cast $ fromMaybe 0 $ index' (4 + rLen + 1) der
  let s = take sLen $ drop (4 + rLen + 2) der
  pure (r, s)
```

---

## 5. Integration with OUC

### 5.1 Upgrade Execution Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Upgrade Execution with t-ECDSA                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Proposal Approved                                                        │
│     └── All auditors signed off                                             │
│                                                                             │
│  2. Build Transaction                                                        │
│     ├── target: Proxy address                                               │
│     ├── data: setImplementation(selector, newImpl)                         │
│     └── chainId, nonce, gas from RPC                                       │
│                                                                             │
│  3. Compute Transaction Hash                                                 │
│     └── keccak256(0x02 || RLP([...]))                                      │
│                                                                             │
│  4. Request t-ECDSA Signature                                               │
│     ├── ic0_call_new("aaaaa-aa", "sign_with_ecdsa")                        │
│     ├── derivation_path: [44', 60', 0', 0', chainId]                       │
│     ├── key_id: { curve: secp256k1, name: "key_1" }                        │
│     └── Attach 25B cycles                                                   │
│                                                                             │
│  5. Await Signature Response                                                 │
│     └── Callback receives signature blob                                    │
│                                                                             │
│  6. Submit Signed Transaction                                               │
│     ├── HTTP Outcall to RPC                                                 │
│     ├── eth_sendRawTransaction                                              │
│     └── Wait for confirmation                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Key Derivation per Chain

Each EVM chain gets a unique derived key:

```
Master Key (t-ECDSA subnet)
    │
    ├── Chain 1 (Ethereum)
    │   └── path: [44', 60', 0', 0', 1]
    │   └── address: 0x...
    │
    ├── Chain 42161 (Arbitrum)
    │   └── path: [44', 60', 0', 0', 42161]
    │   └── address: 0x... (same, derived deterministically)
    │
    └── Chain 8453 (Base)
        └── path: [44', 60', 0', 0', 8453]
        └── address: 0x...
```

---

## 6. Cycle Costs

| Operation | Key | Cycles |
|-----------|-----|--------|
| `sign_with_ecdsa` | `key_1` (production) | 25B |
| `sign_with_ecdsa` | `test_key_1` | 10B |
| `ecdsa_public_key` | any | 0 (free) |

**Budget per Upgrade:**
- 1 signature per chain × 25B cycles = 25B cycles/chain
- Multi-chain (3 chains) = 75B cycles total

---

## 7. Implementation Phases

### Phase 1: Public Key Retrieval
- [ ] C FFI for `ecdsa_public_key`
- [ ] Derivation path encoding
- [ ] Address computation from public key

### Phase 2: Signing
- [ ] C FFI for `sign_with_ecdsa`
- [ ] Async callback handling
- [ ] DER signature decoding

### Phase 3: EVM Transaction
- [ ] EIP-1559 RLP encoding
- [ ] Transaction hash computation
- [ ] Signed transaction encoding

### Phase 4: Integration
- [ ] Hook into `ERC7546/Upgrade.idr`
- [ ] Multi-chain signing coordination
- [ ] Error handling and retry logic

---

## 8. Module Structure

```
idris2-ouc/src/
└── ThresholdECDSA/
    ├── Core.idr          # Types: KeyId, DerivationPath
    ├── FFI.idr           # C FFI bindings
    ├── EvmTx.idr         # EIP-1559 transaction
    ├── Recovery.idr      # Signature recovery
    └── SPEC.toml

lib/ic0/
└── threshold_ecdsa.c     # C implementation
```

---

## 9. References

- [ICP Threshold ECDSA](https://internetcomputer.org/docs/building-apps/network-features/signatures/t-ecdsa)
- [Chain-key signatures overview](https://internetcomputer.org/docs/references/t-sigs-how-it-works)
- [EIP-1559 Transaction Format](https://eips.ethereum.org/EIPS/eip-1559)
- [EIP-155 Replay Protection](https://eips.ethereum.org/EIPS/eip-155)

Sources:
- [Threshold ECDSA | Internet Computer](https://internetcomputer.org/docs/building-apps/network-features/signatures/t-ecdsa)
- [Signing with t-ECDSA | Internet Computer](https://internetcomputer.org/docs/current/developer-docs/smart-contracts/signatures/signing-messages-t-ecdsa)
- [IC Interface Specification](https://internetcomputer.org/docs/references/ic-interface-spec)
