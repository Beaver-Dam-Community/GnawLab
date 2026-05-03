#---------------------------------------
# IAM Role for EC2
#---------------------------------------
resource "aws_iam_role" "ec2_role" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Description = "EC2 role with S3 access for metadata-pivot scenario"
  })
}

#---------------------------------------
# IAM Instance Profile
#---------------------------------------
resource "aws_iam_instance_profile" "ec2_profile" {
  name = local.instance_profile_name
  role = aws_iam_role.ec2_role.name

  tags = local.common_tags
}

#---------------------------------------
# IAM Policy - S3 Access + Self Enumeration
#---------------------------------------
resource "aws_iam_role_policy" "ec2_policy" {
  name = "${local.scenario_name}-policy-${local.scenario_id}"
  role = aws_iam_role.ec2_role.id

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
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy"
        ]
        Resource = aws_iam_role.ec2_role.arn
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
