#---------------------------------------
# S3 Bucket - Sensitive Data Storage
#---------------------------------------
resource "aws_s3_bucket" "data" {
  bucket        = local.s3_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Description = "Simulated sensitive data bucket for s3-data-heist scenario"
  })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy - IP whitelist
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonWhitelistedIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
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

  depends_on = [aws_s3_bucket_public_access_block.data]
}

#---------------------------------------
# S3 Objects - Sensitive Data Files
#---------------------------------------
resource "aws_s3_object" "flag" {
  bucket  = aws_s3_bucket.data.id
  key     = "confidential/flag.txt"
  content = var.flag_value

  tags = merge(local.common_tags, {
    Classification = "TOP SECRET"
  })
}

resource "aws_s3_object" "customers" {
  bucket  = aws_s3_bucket.data.id
  key     = "data/customers.csv"
  content = <<-EOF
    id,name,email,ssn,credit_card
    1,John Doe,john.doe@example.com,123-45-6789,4111-1111-1111-1111
    2,Jane Smith,jane.smith@example.com,987-65-4321,5500-0000-0000-0004
    3,Bob Wilson,bob.wilson@example.com,456-78-9012,3400-0000-0000-009
    4,Alice Brown,alice.brown@example.com,321-54-9876,6011-0000-0000-0004
  EOF

  tags = merge(local.common_tags, {
    Classification = "CONFIDENTIAL"
  })
}

resource "aws_s3_object" "memo" {
  bucket  = aws_s3_bucket.data.id
  key     = "internal/memo.txt"
  content = <<-EOF
    INTERNAL MEMO - Beaver Rides Inc.
    Date: 2024-01-15
    Subject: Q4 Security Audit Results

    Team,

    Our recent security audit identified several areas for improvement:

    1. Credential rotation policy needs enforcement
    2. S3 bucket access logging should be enabled
    3. IAM policies require least-privilege review

    Please address these items by end of Q1.

    - Security Team
  EOF

  tags = merge(local.common_tags, {
    Classification = "INTERNAL"
  })
}

resource "aws_s3_object" "readme" {
  bucket  = aws_s3_bucket.data.id
  key     = "README.txt"
  content = <<-EOF
    Beaver Rides Inc. - Cloud Storage
    ==================================

    This bucket contains company data.
    Authorized personnel only.

    Directory Structure:
    - /data - Customer information
    - /internal - Company memos
    - /confidential - Restricted access
  EOF

  tags = local.common_tags
}
