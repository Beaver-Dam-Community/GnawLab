resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.scenario_name}-artifacts-${local.scenario_id}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # deletes all objects when running terraform destroy

  tags = { Name = "${local.scenario_name}-artifacts-${local.scenario_id}" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
