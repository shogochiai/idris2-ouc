||| Vote Decision Types
module OUC.Types.Validated.Vote

%default total

-- =============================================================================
-- VoteDecision: Replaces Bool for vote approval
-- =============================================================================

||| Vote decision with full context (replaces approve : Bool)
public export
data VoteDecision
  = Approve                 -- Approve the upgrade
  | Reject String           -- Reject with reason
  | RequestChanges String   -- Request modifications
  | Abstain String          -- Abstain from voting

public export
Show VoteDecision where
  show Approve = "Approve"
  show (Reject r) = "Reject: " ++ r
  show (RequestChanges c) = "RequestChanges: " ++ c
  show (Abstain r) = "Abstain: " ++ r

public export
Eq VoteDecision where
  Approve == Approve = True
  (Reject r1) == (Reject r2) = r1 == r2
  (RequestChanges c1) == (RequestChanges c2) = c1 == c2
  (Abstain r1) == (Abstain r2) = r1 == r2
  _ == _ = False

||| Check if decision is approval
public export
isApproval : VoteDecision -> Bool
isApproval Approve = True
isApproval _ = False

||| Check if decision is rejection
public export
isRejection : VoteDecision -> Bool
isRejection (Reject _) = True
isRejection _ = False
