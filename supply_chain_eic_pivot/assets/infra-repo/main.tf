# infra-repo/main.tf (Player's starting point)

provider "aws" {
  region = var.region
}

# 기업의 공용 데이터 보관을 위한 S3 버킷 (정상적인 자원인 척 함)
resource "aws_s3_bucket" "corporate_data" {
  bucket = "beaver-corp-data-storage-${var.environment}"
  
  tags = {
    ManagedBy = "Atlantis"
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
