#---------------------------------------
# IAM User (Leaked Credentials)
#---------------------------------------
resource "aws_iam_user" "attacker" {
  name = local.iam_user_name
  path = "/gnawlab/"

  tags = merge(local.common_tags, {
    Description = "Simulated leaked credentials for ebs-snapshot-theft scenario"
  })
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

#---------------------------------------
# IAM Policy - Enumeration + EC2/EBS Access
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
        Sid    = "EC2SnapshotEnumeration"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2VolumeOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "EC2InstanceOperations"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "EC2KeyPairOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:ImportKeyPair"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2TagOperations"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}
