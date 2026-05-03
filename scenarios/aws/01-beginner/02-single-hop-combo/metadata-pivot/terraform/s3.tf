#---------------------------------------
# S3 Bucket - Sensitive Data Storage
#---------------------------------------
resource "aws_s3_bucket" "data" {
  bucket        = local.s3_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Description = "Simulated sensitive data bucket for metadata-pivot scenario"
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
    id,name,email,account_number,balance
    1,Alice Johnson,alice.j@beaverdambank.com,1001-2345-6789,125000.00
    2,Bob Martinez,bob.m@beaverdambank.com,1001-3456-7890,89500.50
    3,Carol Williams,carol.w@beaverdambank.com,1001-4567-8901,250000.00
    4,David Chen,david.c@beaverdambank.com,1001-5678-9012,45000.75
  EOF

  tags = merge(local.common_tags, {
    Classification = "CONFIDENTIAL"
  })
}

resource "aws_s3_object" "memo" {
  bucket  = aws_s3_bucket.data.id
  key     = "internal/security-memo.txt"
  content = <<-EOF
    INTERNAL MEMO - Beaver Dam Bank
    Date: 2024-02-20
    Subject: IMDS Security Configuration

    Team,

    Following the Capital One incident, we need to review our EC2 configurations:

    1. All new EC2 instances should use IMDSv2 (HttpTokens=required)
    2. Legacy applications need migration plan by Q3
    3. URL fetch features must validate destination addresses

    Current status: Several legacy apps still use IMDSv1.
    Priority: HIGH

    - Cloud Security Team
  EOF

  tags = merge(local.common_tags, {
    Classification = "INTERNAL"
  })
}

resource "aws_s3_object" "readme" {
  bucket  = aws_s3_bucket.data.id
  key     = "README.txt"
  content = <<-EOF
    Beaver Dam Bank - Secure Cloud Storage
    ======================================

    This bucket contains sensitive banking data.
    Access restricted to authorized services only.

    Directory Structure:
    - /data - Customer financial records
    - /internal - Company communications
    - /confidential - Restricted access materials
  EOF

  tags = local.common_tags
}
