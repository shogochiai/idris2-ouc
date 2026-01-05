||| String Case Utilities
|||
||| Case conversion for strings (toLower works on Char, not String).
module Util.StringCase

import Data.String

%default total

||| Convert string to lowercase
public export
strToLower : String -> String
strToLower s = pack $ map toLower $ unpack s

||| Convert string to uppercase
public export
strToUpper : String -> String
strToUpper s = pack $ map toUpper $ unpack s
