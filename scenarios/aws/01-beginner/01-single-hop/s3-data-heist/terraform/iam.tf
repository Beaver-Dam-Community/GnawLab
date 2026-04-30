#---------------------------------------
# IAM User (Leaked Credentials)
#---------------------------------------
resource "aws_iam_user" "attacker" {
  name = local.iam_user_name
  path = "/gnawlab/"

  tags = merge(local.common_tags, {
    Description = "Simulated leaked credentials for s3-data-heist scenario"
  })
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

#---------------------------------------
# IAM Policy - Enumeration + S3 Access
#---------------------------------------
resource "aws_iam_user_policy" "attacker_policy" {
  name = local.iam_policy_name
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
        Sid    = "IAMEnumeration"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUserPolicies",
          "iam:ListAttachedUserPolicies",
          "iam:GetUserPolicy",
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
        Sid    = "S3BucketEnumeration"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3DataAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
      }
    ]
  })
}
