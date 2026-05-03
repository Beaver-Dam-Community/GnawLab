provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "corporate_data" {
  bucket = "beaver-corp-data-storage-${var.environment}"

  tags = {
    ManagedBy   = "Atlantis"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "data_protection" {
  bucket = aws_s3_bucket.corporate_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
