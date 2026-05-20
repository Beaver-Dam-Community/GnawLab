#---------------------------------------
# Flag Bucket
#---------------------------------------
resource "aws_s3_bucket" "flag" {
  bucket        = local.flag_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Description = "Flag bucket for obfuscated-policy scenario"
  })
}

resource "aws_s3_bucket_public_access_block" "flag" {
  bucket = aws_s3_bucket.flag.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flag" {
  bucket = aws_s3_bucket.flag.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IP whitelist: deny non-whitelisted source IPs (AWS service calls exempted)
resource "aws_s3_bucket_policy" "flag" {
  bucket = aws_s3_bucket.flag.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonWhitelistedIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.flag.arn,
          "${aws_s3_bucket.flag.arn}/*"
        ]
        Condition = {
          NotIpAddress = {
            "aws:SourceIp" = local.whitelist_cidr
          }
          Bool = {
            "aws:ViaAWSService" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.flag]
}

resource "aws_s3_object" "flag" {
  bucket  = aws_s3_bucket.flag.id
  key     = "flag.txt"
  content = var.flag_value

  tags = merge(local.common_tags, {
    Classification = "TOP SECRET"
  })
}

#---------------------------------------
# CloudTrail Log Bucket (separate from flag bucket)
#---------------------------------------
resource "aws_s3_bucket" "trail" {
  bucket        = local.trail_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Description = "CloudTrail log destination"
  })
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.trail]
}
