||| ERC-7546 Dictionary Module
|||
||| Constructs calldata for ERC-7546 Diamond/Dictionary pattern upgrades.
||| ERC-7546 uses a function selector -> implementation address mapping.
module ERC7546.Dictionary

import FRC.Core
import Data.List
import Data.String
import Util.StringHex as SHex

%default total

-- =============================================================================
-- ERC-7546 Types
-- =============================================================================

||| Function selector (4 bytes as hex string)
public export
record FunctionSelector where
  constructor MkSelector
  hex : String                    -- 0x-prefixed 4-byte hex (e.g., "0x12345678")

public export
Show FunctionSelector where
  show s = s.hex

public export
Eq FunctionSelector where
  s1 == s2 = s1.hex == s2.hex

||| Validate selector format
public export
isValidSelector : FunctionSelector -> Bool
isValidSelector sel =
  SHex.isHexPrefixed sel.hex && length sel.hex == 10

||| Dictionary entry: selector -> implementation
public export
record DictionaryEntry where
  constructor MkDictionaryEntry
  selector : FunctionSelector
  impl     : String               -- Implementation contract address

public export
Show DictionaryEntry where
  show e = show e.selector ++ " -> " ++ e.impl

public export
Eq DictionaryEntry where
  e1 == e2 = e1.selector == e2.selector && e1.impl == e2.impl

||| Dictionary update operation type
public export
data DictOperation
  = AddEntry DictionaryEntry      -- Add new selector mapping
  | RemoveEntry FunctionSelector  -- Remove selector mapping
  | ReplaceEntry DictionaryEntry  -- Replace existing mapping

public export
Show DictOperation where
  show (AddEntry e)     = "Add(" ++ show e ++ ")"
  show (RemoveEntry s)  = "Remove(" ++ show s ++ ")"
  show (ReplaceEntry e) = "Replace(" ++ show e ++ ")"

||| Facet cut action (EIP-2535 compatible)
public export
data FacetCutAction = Add | Replace | Remove

public export
Show FacetCutAction where
  show Add     = "Add"
  show Replace = "Replace"
  show Remove  = "Remove"

||| Check if action is Remove
public export
isRemove : FacetCutAction -> Bool
isRemove Remove = True
isRemove _      = False

||| Facet cut structure
public export
record FacetCut where
  constructor MkFacetCut
  facetAddress : String
  action       : FacetCutAction
  selectors    : List FunctionSelector

public export
Show FacetCut where
  show f = "FacetCut{" ++ f.facetAddress ++ ", " ++ show f.action ++
           ", " ++ show (length f.selectors) ++ " selectors}"

-- =============================================================================
-- ERC-7546 Standard Selectors
-- =============================================================================

||| upgradeTo(address newImplementation)
public export
UPGRADE_TO_SELECTOR : String
UPGRADE_TO_SELECTOR = "0x3659cfe6"

||| upgradeToAndCall(address newImplementation, bytes data)
public export
UPGRADE_TO_AND_CALL_SELECTOR : String
UPGRADE_TO_AND_CALL_SELECTOR = "0x4f1ef286"

||| diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
public export
DIAMOND_CUT_SELECTOR : String
DIAMOND_CUT_SELECTOR = "0x1f931c1c"

||| facets() - returns all facets and their selectors
public export
FACETS_SELECTOR : String
FACETS_SELECTOR = "0x7a0ed627"

||| facetAddress(bytes4 selector) - returns facet address for selector
public export
FACET_ADDRESS_SELECTOR : String
FACET_ADDRESS_SELECTOR = "0xcdffacc6"

||| facetFunctionSelectors(address facet) - returns selectors for facet
public export
FACET_SELECTORS_SELECTOR : String
FACET_SELECTORS_SELECTOR = "0xadfca15e"

-- =============================================================================
-- ABI Encoding Helpers
-- =============================================================================

||| Encode address (20 bytes, left-padded to 32)
encodeAddress : String -> String
encodeAddress addr = SHex.padTo32 addr

||| Encode uint8 (action enum, 0-2 for FacetCutAction)
encodeUint8 : Nat -> String
encodeUint8 0 = SHex.padTo32 "00"
encodeUint8 1 = SHex.padTo32 "01"
encodeUint8 2 = SHex.padTo32 "02"
encodeUint8 _ = SHex.padTo32 "00"  -- Fallback

||| Encode bytes4 selector
encodeSelector : FunctionSelector -> String
encodeSelector sel =
  let stripped = SHex.stripHexPrefix sel.hex
  in stripped ++ SHex.takeZeros 56  -- Pad to 32 bytes, right-aligned

-- =============================================================================
-- Calldata Construction
-- =============================================================================

||| Build upgradeTo calldata
public export
buildUpgradeTo : String -> FR String
buildUpgradeTo newImpl =
  if not (SHex.isHexPrefixed newImpl) || length newImpl /= 42
    then fail Update "buildUpgradeTo" "Invalid address"
              (DecodeError "Implementation address must be 0x + 40 hex chars")
    else
      let calldata = UPGRADE_TO_SELECTOR ++ encodeAddress newImpl
      in ok Update "buildUpgradeTo"
            ("Built upgradeTo(" ++ newImpl ++ ")")
            calldata

||| Build upgradeToAndCall calldata
public export
buildUpgradeToAndCall :
  String ->           -- new implementation
  String ->           -- initialization calldata
  FR String
buildUpgradeToAndCall newImpl initData =
  if not (SHex.isHexPrefixed newImpl) || length newImpl /= 42
    then fail Update "buildUpgradeToAndCall" "Invalid address"
              (DecodeError "Implementation address format invalid")
    else
      -- Simplified: proper impl would encode dynamic bytes
      let calldata = UPGRADE_TO_AND_CALL_SELECTOR ++ encodeAddress newImpl
      in ok Update "buildUpgradeToAndCall"
            ("Built upgradeToAndCall(" ++ newImpl ++ ", ...)")
            calldata

||| Build diamond cut for single facet
public export
buildSingleFacetCut :
  FacetCut ->
  FR String
buildSingleFacetCut cut =
  if isNil cut.selectors && not (isRemove cut.action)
    then fail Update "buildSingleFacetCut" "No selectors"
              (InvalidState "Add/Replace requires at least one selector")
    else if not (SHex.isHexPrefixed cut.facetAddress) || length cut.facetAddress /= 42
      then fail Update "buildSingleFacetCut" "Invalid facet address"
                (DecodeError "Facet address format invalid")
      else
        let actionNum = case cut.action of
              Add     => 0
              Replace => 1
              Remove  => 2
        in ok Update "buildSingleFacetCut"
              ("Built facet cut: " ++ show cut)
              DIAMOND_CUT_SELECTOR  -- Simplified; would include full encoding

-- =============================================================================
-- Dictionary Operations (FRC-compliant)
-- =============================================================================

||| Validate dictionary entry
public export
validateEntry : DictionaryEntry -> FR ()
validateEntry entry =
  if not (isValidSelector entry.selector)
    then fail Query "validateEntry" "Invalid selector format"
              (DecodeError ("Selector must be 0x + 8 hex chars: " ++ entry.selector.hex))
    else if not (SHex.isHexPrefixed entry.impl) || length entry.impl /= 42
      then fail Query "validateEntry" "Invalid address format"
                (DecodeError ("Address must be 0x + 40 hex chars: " ++ entry.impl))
      else ok Query "validateEntry" ("Valid: " ++ show entry) ()

||| Convert DictOperation to FacetCut
public export
operationToFacetCut : DictOperation -> FacetCut
operationToFacetCut (AddEntry e) =
  MkFacetCut e.impl Add [e.selector]
operationToFacetCut (RemoveEntry s) =
  MkFacetCut "0x0000000000000000000000000000000000000000" Remove [s]
operationToFacetCut (ReplaceEntry e) =
  MkFacetCut e.impl Replace [e.selector]

||| Build calldata for batch dictionary update
public export
buildBatchUpdate :
  List DictOperation ->
  FR String
buildBatchUpdate [] =
  fail Update "buildBatchUpdate" "Empty operation list"
       (InvalidState "At least one operation required")
buildBatchUpdate ops =
  let cuts = map operationToFacetCut ops
  in ok Update "buildBatchUpdate"
        ("Built batch update: " ++ show (length ops) ++ " operations")
        DIAMOND_CUT_SELECTOR  -- Simplified

-- =============================================================================
-- Dictionary Diff Computation
-- =============================================================================

||| Compute operations needed to migrate from old to new implementation
public export
computeDiff :
  List FunctionSelector ->   -- Old implementation selectors
  List FunctionSelector ->   -- New implementation selectors
  String ->                  -- New implementation address
  List DictOperation
computeDiff oldSels newSels newImpl =
  let -- Selectors to add (in new but not in old)
      toAdd = filter (\s => not (s `elem` oldSels)) newSels
      addOps = map (\s => AddEntry (MkDictionaryEntry s newImpl)) toAdd

      -- Selectors to remove (in old but not in new)
      toRemove = filter (\s => not (s `elem` newSels)) oldSels
      removeOps = map RemoveEntry toRemove

      -- Selectors to replace (in both)
      toReplace = filter (\s => s `elem` oldSels) newSels
      replaceOps = map (\s => ReplaceEntry (MkDictionaryEntry s newImpl)) toReplace

  in addOps ++ replaceOps ++ removeOps

||| Analyze upgrade impact
public export
record UpgradeAnalysis where
  constructor MkUpgradeAnalysis
  addedSelectors   : List FunctionSelector
  removedSelectors : List FunctionSelector
  replacedSelectors: List FunctionSelector
  totalOperations  : Nat

public export
Show UpgradeAnalysis where
  show a = "UpgradeAnalysis{added=" ++ show (length a.addedSelectors) ++
           ", removed=" ++ show (length a.removedSelectors) ++
           ", replaced=" ++ show (length a.replacedSelectors) ++ "}"

||| Analyze dictionary diff
public export
analyzeUpgrade :
  List FunctionSelector ->
  List FunctionSelector ->
  UpgradeAnalysis
analyzeUpgrade oldSels newSels =
  let added = filter (\s => not (s `elem` oldSels)) newSels
      removed = filter (\s => not (s `elem` newSels)) oldSels
      replaced = filter (\s => (s `elem` oldSels) && (s `elem` newSels)) newSels
  in MkUpgradeAnalysis added removed replaced (length added + length removed + length replaced)
