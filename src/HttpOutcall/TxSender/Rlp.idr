||| RLP Encoding for EVM Transactions
|||
||| Recursive Length Prefix encoding for EIP-1559 transactions.
module HttpOutcall.TxSender.Rlp

import Data.List
import Data.Bits
import Util.StringHex

%default covering

-- =============================================================================
-- RLP Encoding
-- =============================================================================

||| RLP item (either bytes or list)
public export
data RlpItem
  = RlpBytes (List Bits8)
  | RlpList (List RlpItem)

||| Encode a natural number as bytes (big-endian, no leading zeros)
export
natToBytes : Nat -> List Bits8
natToBytes 0 = []
natToBytes n = natToBytes (n `div` 256) ++ [cast (n `mod` 256)]

||| Encode a natural number as bytes, with minimum length
export
natToBytesMin : Nat -> Nat -> List Bits8
natToBytesMin minLen n =
  let bytes = natToBytes n
      padLen = if length bytes < minLen then minLen `minus` length bytes else 0
  in replicate padLen 0 ++ bytes

||| Encode length prefix for RLP
encodeLength : Nat -> Bits8 -> List Bits8
encodeLength len offset =
  if len < 56
    then [offset + cast len]
    else
      let lenBytes = natToBytes len
          lenLen = length lenBytes
      in [offset + 55 + cast lenLen] ++ lenBytes

||| Encode RLP item to bytes
export
rlpEncode : RlpItem -> List Bits8
rlpEncode (RlpBytes bytes) =
  if length bytes == 1 && (fromMaybe 0 (head' bytes)) < 0x80
    then bytes  -- Single byte < 0x80
    else encodeLength (length bytes) 0x80 ++ bytes
rlpEncode (RlpList items) =
  let encoded = concatMap rlpEncode items
  in encodeLength (length encoded) 0xC0 ++ encoded

||| Encode natural number as RLP bytes
export
rlpNat : Nat -> RlpItem
rlpNat 0 = RlpBytes []
rlpNat n = RlpBytes (natToBytes n)

||| Encode hex string as RLP bytes
export
rlpHex : String -> RlpItem
rlpHex s = RlpBytes (hexToBytes s)

||| Encode address (20 bytes) as RLP
export
rlpAddress : String -> RlpItem
rlpAddress addr =
  let bytes = hexToBytes addr
      padded = replicate (20 `minus` length bytes) 0 ++ bytes
  in RlpBytes (take 20 padded)

-- =============================================================================
-- EIP-1559 Transaction Encoding
-- =============================================================================

||| EIP-1559 transaction fields
public export
record Eip1559Fields where
  constructor MkEip1559Fields
  chainId        : Nat
  nonce          : Nat
  maxPriorityFee : Nat
  maxFeePerGas   : Nat
  gasLimit       : Nat
  to             : String  -- hex address
  value          : Nat
  data_          : String  -- hex calldata
  accessList     : List (String, List String)  -- (address, [slots])

||| Encode access list
encodeAccessList : List (String, List String) -> RlpItem
encodeAccessList items = RlpList (map encodeEntry items)
  where
    encodeEntry : (String, List String) -> RlpItem
    encodeEntry (addr, slots) =
      RlpList [rlpAddress addr, RlpList (map rlpHex slots)]

||| Encode EIP-1559 transaction for signing (without signature)
||| Returns: 0x02 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList])
export
encodeEip1559ForSigning : Eip1559Fields -> List Bits8
encodeEip1559ForSigning tx =
  let fields = RlpList
        [ rlpNat tx.chainId
        , rlpNat tx.nonce
        , rlpNat tx.maxPriorityFee
        , rlpNat tx.maxFeePerGas
        , rlpNat tx.gasLimit
        , rlpAddress tx.to
        , rlpNat tx.value
        , rlpHex tx.data_
        , encodeAccessList tx.accessList
        ]
  in 0x02 :: rlpEncode fields

||| Encode EIP-1559 transaction with signature
||| Returns: 0x02 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, v, r, s])
export
encodeEip1559Signed : Eip1559Fields -> Bits8 -> List Bits8 -> List Bits8 -> List Bits8
encodeEip1559Signed tx v r s =
  let fields = RlpList
        [ rlpNat tx.chainId
        , rlpNat tx.nonce
        , rlpNat tx.maxPriorityFee
        , rlpNat tx.maxFeePerGas
        , rlpNat tx.gasLimit
        , rlpAddress tx.to
        , rlpNat tx.value
        , rlpHex tx.data_
        , encodeAccessList tx.accessList
        , rlpNat (cast v)
        , RlpBytes r
        , RlpBytes s
        ]
  in 0x02 :: rlpEncode fields

-- =============================================================================
-- Helpers
-- =============================================================================

||| Convert RLP bytes to hex string
export
rlpToHex : List Bits8 -> String
rlpToHex = bytesToHex

||| Compute transaction hash (keccak256 of encoded tx)
||| Note: Actual keccak256 requires external implementation
export
txHashPlaceholder : List Bits8 -> String
txHashPlaceholder bytes =
  "0x" ++ bytesToHex (take 32 (bytes ++ replicate 32 0))
