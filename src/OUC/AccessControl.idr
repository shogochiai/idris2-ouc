||| OUC Access Control
|||
||| Permission system for OUC canister operations.
||| Three principal types with different access levels:
||| - Controller: Full admin access
||| - Auditor: Proposal review access
||| - Anonymous: Read-only query access
|||
||| ICP Principal-based authentication.
module OUC.AccessControl

import OUC.Functions.Core
import Data.List
import Data.String

%default total

-- =============================================================================
-- Principal Types (5.3.3)
-- =============================================================================

||| Principal role classification
public export
data Role
  = Controller    -- Full admin (canister controller)
  | Auditor       -- Registered auditor
  | Subscriber    -- Protocol subscriber
  | Anonymous     -- Unauthenticated query

public export
Show Role where
  show Controller = "Controller"
  show Auditor    = "Auditor"
  show Subscriber = "Subscriber"
  show Anonymous  = "Anonymous"

public export
Eq Role where
  Controller == Controller = True
  Auditor    == Auditor    = True
  Subscriber == Subscriber = True
  Anonymous  == Anonymous  = True
  _          == _          = False

-- =============================================================================
-- Permission Types
-- =============================================================================

||| Operation permission
public export
data Permission
  -- Query permissions (read-only)
  = QueryAuditors
  | QueryProposals
  | QuerySubscription
  | QueryTreasury
  | QueryOUStatus
  -- Update permissions (state-changing)
  | RegisterAuditor
  | RemoveAuditor
  | AssignOU
  | SubmitReview
  | SetTier
  | SetAutoRenew
  | RegisterOU
  | UpdateOUChain
  -- Admin permissions
  | SetController
  | UpgradeCanister

public export
Eq Permission where
  QueryAuditors     == QueryAuditors     = True
  QueryProposals    == QueryProposals    = True
  QuerySubscription == QuerySubscription = True
  QueryTreasury     == QueryTreasury     = True
  QueryOUStatus     == QueryOUStatus     = True
  RegisterAuditor   == RegisterAuditor   = True
  RemoveAuditor     == RemoveAuditor     = True
  AssignOU          == AssignOU          = True
  SubmitReview      == SubmitReview      = True
  SetTier           == SetTier           = True
  SetAutoRenew      == SetAutoRenew      = True
  RegisterOU        == RegisterOU        = True
  UpdateOUChain     == UpdateOUChain     = True
  SetController     == SetController     = True
  UpgradeCanister   == UpgradeCanister   = True
  _                 == _                 = False

public export
Show Permission where
  show QueryAuditors      = "query:auditors"
  show QueryProposals     = "query:proposals"
  show QuerySubscription  = "query:subscription"
  show QueryTreasury      = "query:treasury"
  show QueryOUStatus      = "query:ou_status"
  show RegisterAuditor    = "update:register_auditor"
  show RemoveAuditor      = "update:remove_auditor"
  show AssignOU           = "update:assign_ou"
  show SubmitReview       = "update:submit_review"
  show SetTier            = "update:set_tier"
  show SetAutoRenew       = "update:set_auto_renew"
  show RegisterOU         = "update:register_ou"
  show UpdateOUChain      = "update:update_ou_chain"
  show SetController      = "admin:set_controller"
  show UpgradeCanister    = "admin:upgrade_canister"

-- =============================================================================
-- Role-Permission Matrix
-- =============================================================================

||| Query permissions available to all roles
queryPermissions : List Permission
queryPermissions =
  [ QueryAuditors
  , QueryProposals
  , QuerySubscription
  , QueryTreasury
  , QueryOUStatus
  ]

||| Permissions for Controller role
controllerPermissions : List Permission
controllerPermissions = queryPermissions ++
  [ RegisterAuditor
  , RemoveAuditor
  , AssignOU
  , SetTier
  , SetAutoRenew
  , RegisterOU
  , UpdateOUChain
  , SetController
  , UpgradeCanister
  ]

||| Permissions for Auditor role
auditorPermissions : List Permission
auditorPermissions = queryPermissions ++
  [ SubmitReview
  ]

||| Permissions for Subscriber role
subscriberPermissions : List Permission
subscriberPermissions = queryPermissions ++
  [ SetTier
  , SetAutoRenew
  ]

||| Permissions for Anonymous role
anonymousPermissions : List Permission
anonymousPermissions = queryPermissions

||| Get permissions for a role
public export
rolePermissions : Role -> List Permission
rolePermissions Controller = controllerPermissions
rolePermissions Auditor    = auditorPermissions
rolePermissions Subscriber = subscriberPermissions
rolePermissions Anonymous  = anonymousPermissions

-- =============================================================================
-- Access Control Context
-- =============================================================================

||| Access control context for a request
public export
record AccessContext where
  constructor MkAccessContext
  callerPrincipal : String
  role            : Role
  auditorId       : Maybe AuditorId    -- If caller is auditor
  controllerPrincipal : String         -- Canister controller

||| Create context for anonymous caller
public export
anonymousContext : String -> AccessContext
anonymousContext controller = MkAccessContext
  "2vxsx-fae"  -- Anonymous principal
  Anonymous
  Nothing
  controller

||| Create context for authenticated caller
public export
authenticatedContext : String -> Role -> Maybe AuditorId -> String -> AccessContext
authenticatedContext caller role auditorId controller =
  MkAccessContext caller role auditorId controller

-- =============================================================================
-- Permission Checking
-- =============================================================================

||| Check if role has permission
public export
hasPermission : Role -> Permission -> Bool
hasPermission role perm = perm `elem` rolePermissions role

||| Check if context allows permission
public export
checkPermission : AccessContext -> Permission -> Bool
checkPermission ctx perm = hasPermission ctx.role perm

||| Access control result
public export
data AccessResult
  = Allowed
  | Denied String

public export
Show AccessResult where
  show Allowed = "Allowed"
  show (Denied reason) = "Denied: " ++ reason

||| Require permission or fail
public export
requirePermission : AccessContext -> Permission -> AccessResult
requirePermission ctx perm =
  if checkPermission ctx perm
    then Allowed
    else Denied ("Permission " ++ show perm ++ " denied for role " ++ show ctx.role)

-- =============================================================================
-- Role Resolution
-- =============================================================================

||| Resolve role from principal
||| Priority: Controller > Auditor > Subscriber > Anonymous
public export
resolveRole : String -> String -> List Auditor -> List String -> Role
resolveRole caller controller auditors subscribers =
  if caller == controller
    then Controller
  else if isAuditor caller auditors
    then Auditor
  else if caller `elem` subscribers
    then Subscriber
  else Anonymous
  where
    isAuditor : String -> List Auditor -> Bool
    isAuditor p [] = False
    isAuditor p (a :: as) =
      if a.id.principal.text == p
        then True
        else isAuditor p as

||| Find auditor by principal
public export
findAuditor : String -> List Auditor -> Maybe AuditorId
findAuditor _ [] = Nothing
findAuditor p (a :: as) =
  if a.id.principal.text == p
    then Just a.id
    else findAuditor p as

-- =============================================================================
-- Access Guard (for canister entry points)
-- =============================================================================

||| Guard canister operation with access control
public export
accessGuard : AccessContext -> Permission -> Either String ()
accessGuard ctx perm =
  case requirePermission ctx perm of
    Allowed => Right ()
    Denied reason => Left reason

||| Guard for query operations (always allowed)
public export
queryGuard : AccessContext -> Either String ()
queryGuard _ = Right ()

||| Guard for controller-only operations
public export
controllerGuard : AccessContext -> Either String ()
controllerGuard ctx =
  if ctx.role == Controller
    then Right ()
    else Left "Controller access required"

||| Guard for auditor operations
public export
auditorGuard : AccessContext -> Either String ()
auditorGuard ctx =
  case ctx.role of
    Controller => Right ()
    Auditor => Right ()
    _ => Left "Auditor access required"

-- =============================================================================
-- Principal Validation
-- =============================================================================

||| Check if principal is valid ICP format
||| Format: xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxxxx-xxx
public export
isValidPrincipal : String -> Bool
isValidPrincipal p =
  let dashCount = length (filter (== '-') (unpack p))
      validPartCount = dashCount >= 4 && dashCount <= 9
      validChars = all (\c => isAlphaNum c || c == '-') (unpack p)
  in validPartCount && validChars && length p >= 20

||| Check if principal is anonymous
public export
isAnonymous : String -> Bool
isAnonymous "2vxsx-fae" = True
isAnonymous _ = False
