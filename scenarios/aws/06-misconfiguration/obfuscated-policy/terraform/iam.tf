#---------------------------------------
# Permission Boundary
# Acts as the single-account equivalent of an SCP. Caps the attacker's
# maximum effective permissions regardless of what the attacker grants
# themselves through obfuscated policies. This is what stops escalation
# paths (CreateUser, AssumeRole, tampering with the detector, etc.) so
# the Detection Lambda only has to focus on scenario-relevant patterns.
#---------------------------------------
resource "aws_iam_policy" "attacker_boundary" {
  name        = "${local.scenario_name}-boundary-${local.scenario_id}"
  description = "Maximum permissions ceiling for the attacker user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity",
        "iam:GetUser",
        "iam:ListUserPolicies",
        "iam:GetUserPolicy",
        "iam:ListAttachedUserPolicies",
        "iam:ListGroupsForUser",
        "iam:ListGroupPolicies",
        "iam:ListAttachedGroupPolicies",
        "iam:GetGroupPolicy",
        "iam:CreatePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:AttachUserPolicy",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListAllMyBuckets",
        "s3:ListBucket"
      ]
      Resource = "*"
    }]
  })

  tags = local.common_tags
}

#---------------------------------------
# Attacker IAM User (Leaked Credentials)
#---------------------------------------
resource "aws_iam_user" "attacker" {
  name                 = local.iam_user_name
  path                 = "/gnawlab/"
  force_destroy        = true
  permissions_boundary = aws_iam_policy.attacker_boundary.arn

  tags = merge(local.common_tags, {
    Description = "Simulated leaked attacker user for obfuscated-policy scenario"
  })
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

#---------------------------------------
# Attacker baseline permissions
# - identity / self enumeration
# - iam:CreatePolicy + iam:AttachUserPolicy (entry point for the bypass)
# - sufficient s3:List* on the flag bucket itself is intentionally NOT given;
#   the attacker must obtain bucket discovery via a wildcard-obfuscated policy.
#---------------------------------------
resource "aws_iam_user_policy" "attacker_policy" {
  name = local.iam_user_policy_name
  user = aws_iam_user.attacker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IdentityVerification"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Sid    = "SelfEnumeration"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupsForUser",
          "iam:ListGroupPolicies",
          "iam:ListAttachedGroupPolicies",
          "iam:GetGroupPolicy"
        ]
        Resource = [
          aws_iam_user.attacker.arn,
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/*"
        ]
      },
      {
        Sid    = "PolicyCreationAndSelfAttach"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = "*"
      },
      {
        Sid    = "AttachOwnedPolicy"
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy"
        ]
        Resource = aws_iam_user.attacker.arn
      }
    ]
  })
}

#---------------------------------------
# Detection Lambda execution role
#---------------------------------------
resource "aws_iam_role" "detector_lambda" {
  name = local.detector_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "detector_basic" {
  role       = aws_iam_role.detector_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "detector_iam" {
  name = "${local.scenario_name}-detector-iam-${local.scenario_id}"
  role = aws_iam_role.detector_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAndDeleteCustomerPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListEntitiesForPolicy",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:DetachUserPolicy",
          "iam:DetachGroupPolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}
