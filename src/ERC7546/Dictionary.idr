||| ERC-7546 Upgradeable Clone Module
|||
||| Constructs calldata for ERC-7546 Upgradeable Clone upgrades.
||| ERC-7546 clones can be upgraded to new implementations via upgradeTo().
||| NOT Diamond pattern - each clone has a single implementation address.
module ERC7546.Dictionary

import FRMonad.Core
import Data.List
import Data.String
import Util.StringHex as SHex

%default total

-- =============================================================================
-- ERC-7546 Upgradeable Clone Types
-- =============================================================================

||| Clone instance identifier
public export
record CloneId where
  constructor MkCloneId
  address : String  -- Clone contract address (0x + 40 hex)

public export
Show CloneId where
  show c = c.address

public export
Eq CloneId where
  c1 == c2 = c1.address == c2.address

||| Implementation version info
public export
record ImplementationInfo where
  constructor MkImplementationInfo
  address : String        -- Implementation contract address
  version : Nat           -- Version number
  codeHash : String       -- Hash of implementation bytecode

public export
Show ImplementationInfo where
  show i = "Impl{" ++ i.address ++ ", v" ++ show i.version ++ "}"

-- =============================================================================
-- ERC-7546 Standard Selectors
-- =============================================================================

||| upgradeTo(address newImplementation)
||| keccak256("upgradeTo(address)")[:4]
public export
UPGRADE_TO_SELECTOR : String
UPGRADE_TO_SELECTOR = "0x3659cfe6"

||| upgradeToAndCall(address newImplementation, bytes data)
||| keccak256("upgradeToAndCall(address,bytes)")[:4]
public export
UPGRADE_TO_AND_CALL_SELECTOR : String
UPGRADE_TO_AND_CALL_SELECTOR = "0x4f1ef286"

||| implementation() - returns current implementation address
||| keccak256("implementation()")[:4]
public export
IMPLEMENTATION_SELECTOR : String
IMPLEMENTATION_SELECTOR = "0x5c60da1b"

-- =============================================================================
-- Address Validation
-- =============================================================================

||| Validate Ethereum address format (0x + 40 hex chars)
public export
isValidEthAddress : String -> Bool
isValidEthAddress addr =
  SHex.isHexPrefixed addr && strLength addr == 42

||| Validate implementation address
public export
validateImplementation : String -> FR ()
validateImplementation addr =
  if isValidEthAddress addr
    then ok Query "validateImplementation" ("Valid: " ++ addr) ()
    else fail Query "validateImplementation" "Invalid address format"
              (DecodeError "Implementation address must be 0x + 40 hex chars")

-- =============================================================================
-- ABI Encoding Helpers
-- =============================================================================

||| Encode address (20 bytes, left-padded to 32)
encodeAddress : String -> String
encodeAddress addr = SHex.padTo32 addr

-- =============================================================================
-- Calldata Construction
-- =============================================================================

||| Build upgradeTo calldata
||| Used to upgrade a clone to a new implementation
public export
buildUpgradeTo : String -> FR String
buildUpgradeTo newImpl =
  if not (isValidEthAddress newImpl)
    then fail Update "buildUpgradeTo" "Invalid address"
              (DecodeError "Implementation address must be 0x + 40 hex chars")
    else
      let calldata = UPGRADE_TO_SELECTOR ++ encodeAddress newImpl
      in ok Update "buildUpgradeTo"
            ("Built upgradeTo(" ++ newImpl ++ ")")
            calldata

||| Build upgradeToAndCall calldata
||| Upgrades and calls initialization function atomically
public export
buildUpgradeToAndCall :
  String ->           -- new implementation address
  String ->           -- initialization calldata (hex)
  FR String
buildUpgradeToAndCall newImpl initData =
  if not (isValidEthAddress newImpl)
    then fail Update "buildUpgradeToAndCall" "Invalid address"
              (DecodeError "Implementation address format invalid")
    else if not (SHex.isHexPrefixed initData)
      then fail Update "buildUpgradeToAndCall" "Invalid init data"
                (DecodeError "Init data must be hex")
      else
        -- ABI encode: selector + address (padded) + offset + length + data
        let addrEncoded = encodeAddress newImpl
            dataStripped = SHex.stripHexPrefix initData
            dataLen = strLength dataStripped `div` 2
            -- Simplified encoding
            calldata = UPGRADE_TO_AND_CALL_SELECTOR ++ addrEncoded
        in ok Update "buildUpgradeToAndCall"
              ("Built upgradeToAndCall(" ++ newImpl ++ ", " ++ show dataLen ++ " bytes)")
              calldata

||| Build implementation() query calldata
public export
buildGetImplementation : String
buildGetImplementation = IMPLEMENTATION_SELECTOR

-- =============================================================================
-- Upgrade Analysis
-- =============================================================================

||| Clone upgrade request (simple, for single clone)
public export
record CloneUpgradeRequest where
  constructor MkCloneUpgradeRequest
  cloneAddress : String           -- Clone to upgrade
  currentImpl : String            -- Current implementation
  newImpl : String                -- New implementation to upgrade to
  initCalldata : Maybe String     -- Optional init calldata

public export
Show CloneUpgradeRequest where
  show r = "CloneUpgrade{" ++ r.cloneAddress ++ ": " ++
           r.currentImpl ++ " -> " ++ r.newImpl ++ "}"

||| Validate clone upgrade request
public export
validateCloneUpgradeRequest : CloneUpgradeRequest -> FR ()
validateCloneUpgradeRequest req = do
  _ <- validateImplementation req.cloneAddress
  _ <- validateImplementation req.currentImpl
  _ <- validateImplementation req.newImpl
  -- Ensure not upgrading to same implementation
  if req.currentImpl == req.newImpl
    then fail Update "validateCloneUpgradeRequest" "Same implementation"
              (InvalidState "Cannot upgrade to current implementation")
    else ok Update "validateCloneUpgradeRequest" ("Valid: " ++ show req) ()

||| Build calldata for clone upgrade request
public export
buildCloneUpgradeCalldata : CloneUpgradeRequest -> FR String
buildCloneUpgradeCalldata req = do
  _ <- validateCloneUpgradeRequest req
  case req.initCalldata of
    Nothing => buildUpgradeTo req.newImpl
    Just initData => buildUpgradeToAndCall req.newImpl initData
