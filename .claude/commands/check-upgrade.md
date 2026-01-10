---
description: Check ERC-7546 upgrade status and detect pending changes
allowed-tools: Bash,Read,Grep
argument-hint: [dictionary-addr] [rpc-url]
---

# Check Upgrade Status

Detect pending upgrades by comparing ERC-7546 Dictionary state.

## Arguments

- `$1`: Dictionary contract address (optional, uses env DICTIONARY_ADDR)
- `$2`: RPC URL (optional, uses env RPC_URL or default)

## Steps

1. **Get Dictionary Address**
   ```bash
   DICT="${1:-$DICTIONARY_ADDR}"
   RPC="${2:-${RPC_URL:-https://eth.llamarpc.com}}"
   ```

2. **Query Current State**
   - Get owner address
   - Get known selector implementations
   - Check for zombie references (impl without code)

3. **Compare with Local Handlers**
   - Read SPEC.toml for expected selectors
   - Match against deployed implementations
   - Report mismatches

4. **Generate Report**
   Output format:
   ```
   === Upgrade Status Report ===
   Dictionary: 0x...
   Owner: 0x...
   Block: 12345678

   Selectors:
     0x12345678: MATCH (0x... -> 0x...)
     0xabcdef01: MISMATCH (expected 0x..., got 0x...)
     0xdeadbeef: MISSING (not deployed)

   Risk Level: [CRITICAL|HIGH|MEDIUM|LOW|NONE]
   Recommended Auditors: N
   ```

## Usage

```
/check-upgrade 0x1234...abcd https://mainnet.infura.io/v3/...
```

Or with environment variables:
```
export DICTIONARY_ADDR=0x1234...abcd
export RPC_URL=https://mainnet.infura.io/v3/...
/check-upgrade
```

## Integration

This command uses the `lazy evm-lifecycle ask` analysis:
```bash
cd ~/code/lazy && lazy evm-lifecycle ask $TARGET_DIR --dictionary=$DICT --rpc=$RPC
```
