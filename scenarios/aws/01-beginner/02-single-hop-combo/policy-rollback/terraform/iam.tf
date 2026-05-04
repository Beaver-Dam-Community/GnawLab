#---------------------------------------
# IAM User (Leaked Credentials)
#---------------------------------------
resource "aws_iam_user" "attacker" {
  name = local.iam_user_name
  path = "/gnawlab/"

  tags = merge(local.common_tags, {
    Description = "Simulated leaked credentials for policy-rollback scenario"
  })
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

#---------------------------------------
# Customer Managed Policy - Version 1 (Default)
# Restricted: IAM enumeration + SetDefaultPolicyVersion only
# This is the CURRENT policy after security team restricted access
#---------------------------------------
resource "aws_iam_policy" "versioned_policy" {
  name        = local.iam_policy_name
  description = "Policy for ${local.iam_user_name} - restricted after incident response"
  path        = "/gnawlab/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "IdentityVerification"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Sid    = "IAMEnumeration"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUserPolicies",
          "iam:ListAttachedUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListGroupsForUser"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/gnawlab/${local.iam_user_name}"
      },
      {
        Sid    = "PolicyVersionEnumeration"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:ListPolicyVersions",
          "iam:GetPolicyVersion"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/gnawlab/${local.iam_policy_name}"
      },
      {
        # VULNERABLE: This permission allows rollback to previous policy versions
        Sid      = "PolicyVersionRollback"
        Effect   = "Allow"
        Action   = ["iam:SetDefaultPolicyVersion"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/gnawlab/${local.iam_policy_name}"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "attacker" {
  user       = aws_iam_user.attacker.name
  policy_arn = aws_iam_policy.versioned_policy.arn
}

#---------------------------------------
# Policy Version 2: Added secretsmanager:ListSecrets (intermediate)
# Created via AWS CLI because Terraform doesn't support multiple policy versions
#---------------------------------------
resource "null_resource" "policy_version_2" {
  depends_on = [aws_iam_policy.versioned_policy]

  provisioner "local-exec" {
    command = <<-EOT
      aws iam create-policy-version \
        --policy-arn ${aws_iam_policy.versioned_policy.arn} \
        --policy-document file://${path.module}/policies/v2.json \
        --no-set-as-default \
        --profile ${var.profile} \
        --region ${var.region}
    EOT
  }
}

#---------------------------------------
# Policy Version 3: Full Secrets Manager access (incident response elevated)
# This is the TARGET version that attackers want to rollback to
#---------------------------------------
resource "null_resource" "policy_version_3" {
  depends_on = [null_resource.policy_version_2]

  provisioner "local-exec" {
    command = <<-EOT
      aws iam create-policy-version \
        --policy-arn ${aws_iam_policy.versioned_policy.arn} \
        --policy-document file://${path.module}/policies/v3.json \
        --no-set-as-default \
        --profile ${var.profile} \
        --region ${var.region}
    EOT
  }
}
