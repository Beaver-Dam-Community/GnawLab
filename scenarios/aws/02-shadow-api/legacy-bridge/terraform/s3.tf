resource "aws_s3_bucket" "prime_pii_vault_s3" {
  bucket        = "prime-pii-vault-${local.suffix}"
  force_destroy = true

  tags = {
    Name        = "prime-pii-vault-${local.suffix}"
    DataClass   = "pii"
    Sensitivity = "high"
  }
}

resource "aws_s3_bucket_public_access_block" "pii_vault_pab" {
  bucket = aws_s3_bucket.prime_pii_vault_s3.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pii_vault_sse" {
  bucket = aws_s3_bucket.prime_pii_vault_s3.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "customer_credit_applications_object" {
  bucket       = aws_s3_bucket.prime_pii_vault_s3.id
  key          = "applications/customer_credit_applications.csv"
  source       = "${path.module}/../assets/seed_data/customer_credit_applications.csv"
  etag         = filemd5("${path.module}/../assets/seed_data/customer_credit_applications.csv")
  content_type = "text/csv"

  tags = {
    Type      = "dummy-pii"
    DataClass = "pii"
  }
}

resource "aws_s3_object" "migration_log_object" {
  bucket       = aws_s3_bucket.prime_pii_vault_s3.id
  key          = "applications/migration_log.txt"
  content      = "v3->v5 migration window: 2024-08-12 to 2024-09-01.\nLegacy v1 backend retained for media-caching parity until further notice.\n"
  content_type = "text/plain"

  tags = {
    Type = "decoy"
  }
}

resource "aws_s3_object" "q1_summary_object" {
  bucket       = aws_s3_bucket.prime_pii_vault_s3.id
  key          = "applications/q1_2024_summary.txt"
  content      = "Q1 2024 underwriting throughput summary - approved 81.4% of 142,003 applications.\n"
  content_type = "text/plain"

  tags = {
    Type = "decoy"
  }
}

resource "aws_s3_object" "breach_notice_object" {
  bucket = aws_s3_bucket.prime_pii_vault_s3.id
  key    = "confidential/breach_notice.txt"
  content = templatefile("${path.module}/../assets/seed_data/breach_notice.txt.tftpl", {
    flag = var.flag_value
  })
  content_type = "text/plain"

  tags = {
    Type      = "scenario-flag"
    DataClass = "secret"
  }
}