# Two S3 buckets:
#   1. workspace bucket  - holds tenant documents (FAQ, manuals, customer exports)
#   2. console bucket    - serves the static SaaS console / customer widget assets
#                          via CloudFront

# ============================================================
# Workspace bucket (FitMall tenant data)
# ============================================================

resource "aws_s3_bucket" "workspace" {
  bucket        = "${local.name_prefix}-workspace"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "workspace" {
  bucket                  = aws_s3_bucket.workspace.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.workspace.arn
    }
    # Bucket Key is intentionally DISABLED so the SSE-KMS encryption context
    # is per-object (object ARN). The intended (but absent) prefix-based KMS
    # condition design relied on this, but that design was dropped in v4.0
    # because it would have blocked seller_admin's own legitimate exports.
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_versioning" "workspace" {
  bucket = aws_s3_bucket.workspace.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "workspace_kb_sync" {
  bucket = aws_s3_bucket.workspace.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.kb_ingestion_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "public/"
  }

  depends_on = [
    aws_lambda_permission.kb_ingestion_trigger_s3,
  ]
}

# Seed the bucket prefix structure so the KB data source has something to point at.
resource "aws_s3_object" "prefix_public_faq" {
  bucket  = aws_s3_bucket.workspace.id
  key     = "public/faq/.keep"
  content = "TokTok-Support FAQ prefix\n"
}

resource "aws_s3_object" "prefix_public_manuals" {
  bucket  = aws_s3_bucket.workspace.id
  key     = "public/manuals/.keep"
  content = "TokTok-Support manuals prefix\n"
}

resource "aws_s3_object" "prefix_admin_customers" {
  bucket  = aws_s3_bucket.workspace.id
  key     = "admin-only/customers/.keep"
  content = "TokTok-Support admin-only customers prefix\n"
}

resource "aws_s3_object" "prefix_admin_sales" {
  bucket  = aws_s3_bucket.workspace.id
  key     = "admin-only/sales/.keep"
  content = "TokTok-Support admin-only sales prefix\n"
}

# Seed FAQ documents (public, KB-indexed)
resource "aws_s3_object" "seed_faq_refund" {
  bucket = aws_s3_bucket.workspace.id
  key    = "public/faq/refund-policy-v3.md"
  source = "${path.module}/../assets/kb_seed/refund-policy-v3.md"
  etag   = filemd5("${path.module}/../assets/kb_seed/refund-policy-v3.md")
}

resource "aws_s3_object" "seed_faq_exchange" {
  bucket = aws_s3_bucket.workspace.id
  key    = "public/faq/exchange-policy-v2.md"
  source = "${path.module}/../assets/kb_seed/exchange-policy-v2.md"
  etag   = filemd5("${path.module}/../assets/kb_seed/exchange-policy-v2.md")
}

resource "aws_s3_object" "seed_faq_shipping" {
  bucket = aws_s3_bucket.workspace.id
  # The KB-side document_id is derived from the S3 key by chat_backend
  # (strip "public/" prefix and ".md" suffix). To keep that derivation
  # aligned with the document_catalog logical IDs ("faq/shipping",
  # "manual/size-guide"), the upload keys mirror the catalog IDs even
  # when the source filename in assets/kb_seed differs.
  key    = "public/faq/shipping.md"
  source = "${path.module}/../assets/kb_seed/shipping-faq.md"
  etag   = filemd5("${path.module}/../assets/kb_seed/shipping-faq.md")
}

resource "aws_s3_object" "seed_manual_size_guide" {
  bucket = aws_s3_bucket.workspace.id
  key    = "public/manual/size-guide.md"
  source = "${path.module}/../assets/kb_seed/size-guide.md"
  etag   = filemd5("${path.module}/../assets/kb_seed/size-guide.md")
}

# Seed the admin-only customer export CSV (the protected target).
resource "aws_s3_object" "seed_customer_export" {
  bucket = aws_s3_bucket.workspace.id
  key    = local.customer_export_s3_key
  source = "${path.module}/../assets/catalog_seed/customer-export-2026-04.csv"
  etag   = filemd5("${path.module}/../assets/catalog_seed/customer-export-2026-04.csv")
}

# ============================================================
# Console hosting bucket (SaaS console + customer widget assets)
# ============================================================

resource "aws_s3_bucket" "console" {
  bucket        = "${local.name_prefix}-console"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "console" {
  bucket                  = aws_s3_bucket.console.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "console" {
  bucket = aws_s3_bucket.console.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow CloudFront OAC to read.
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.console.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.console.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "console" {
  bucket = aws_s3_bucket.console.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Console index + assets are uploaded via aws_s3_object resources defined in
# web.tf (kept separate so phase ordering is clear).
