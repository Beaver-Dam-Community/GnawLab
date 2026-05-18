resource "aws_iam_role" "lambda_exec" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Description = "Lambda execution role with over-permissive vault access"
  })
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = local.lambda_policy_name
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "UploadsRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      },
      {
        Sid    = "VaultWildcard"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          aws_s3_bucket.vault.arn,
          "${aws_s3_bucket.vault.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "portal" {
  name = local.portal_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Description = "Portal EC2 role for S3 upload and Lambda invocation"
  })
}

resource "aws_iam_instance_profile" "portal" {
  name = local.portal_profile_name
  role = aws_iam_role.portal.name

  tags = local.common_tags
}

resource "aws_iam_role_policy" "portal_policy" {
  name = local.portal_policy_name
  role = aws_iam_role.portal.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UploadToIngestBucket"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/uploads/*"
      },
      {
        Sid    = "InvokeProcessor"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.process_upload.arn
      }
    ]
  })
}

resource "aws_iam_role" "guardduty_malware" {
  name = local.gd_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "malware-protection-plan.guardduty.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Description = "GuardDuty Malware Protection role for uploads bucket"
  })
}

resource "aws_iam_role_policy" "guardduty_malware_policy" {
  name = "guardduty-malware-protection-policy"
  role = aws_iam_role.guardduty_malware.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3GetObject"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Sid    = "S3TagObject"
        Effect = "Allow"
        Action = ["s3:PutObjectTagging", "s3:GetObjectTagging"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.uploads.arn
      },
      {
        Sid    = "S3BucketNotification"
        Effect = "Allow"
        Action = [
          "s3:GetBucketNotification",
          "s3:PutBucketNotification"
        ]
        Resource = aws_s3_bucket.uploads.arn
      },
      {
        Sid    = "EventBridgeManagedRule"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:DeleteRule",
          "events:RemoveTargets",
          "events:DescribeRule"
        ]
        Resource = "arn:aws:events:${var.region}:${data.aws_caller_identity.current.account_id}:rule/*"
      }
    ]
  })
}
