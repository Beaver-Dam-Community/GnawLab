# document_catalog table — maps logical document IDs to S3 objects.
# Both public FAQ links and admin-only customer exports flow through the
# same source_link_issuer Lambda, which looks up entries here. The
# `required_role` attribute is the document-level permission that
# source_link_issuer is *supposed* to compare against the caller's JWT
# group claim before issuing a presigned URL. That comparison is missing
# in source_link_issuer Lambda code (the documented vulnerability).

resource "aws_dynamodb_table" "document_catalog" {
  name         = "${local.name_prefix}-document-catalog"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "document_id"

  attribute {
    name = "document_id"
    type = "S"
  }
}

# Public FAQ + manual entries (no required_role -> any caller can fetch URL).
resource "aws_dynamodb_table_item" "catalog_faq_refund" {
  table_name = aws_dynamodb_table.document_catalog.name
  hash_key   = aws_dynamodb_table.document_catalog.hash_key

  item = jsonencode({
    document_id   = { S = "faq/refund-policy-v3" }
    s3_bucket     = { S = aws_s3_bucket.workspace.id }
    s3_key        = { S = "public/faq/refund-policy-v3.md" }
    title         = { S = "Refund Policy v3.0" }
    content_type  = { S = "text/markdown" }
    required_role = { S = "public" }
  })
}

resource "aws_dynamodb_table_item" "catalog_faq_exchange" {
  table_name = aws_dynamodb_table.document_catalog.name
  hash_key   = aws_dynamodb_table.document_catalog.hash_key

  item = jsonencode({
    document_id   = { S = "faq/exchange-policy-v2" }
    s3_bucket     = { S = aws_s3_bucket.workspace.id }
    s3_key        = { S = "public/faq/exchange-policy-v2.md" }
    title         = { S = "Exchange Policy v2.0" }
    content_type  = { S = "text/markdown" }
    required_role = { S = "public" }
  })
}

resource "aws_dynamodb_table_item" "catalog_faq_shipping" {
  table_name = aws_dynamodb_table.document_catalog.name
  hash_key   = aws_dynamodb_table.document_catalog.hash_key

  item = jsonencode({
    document_id   = { S = "faq/shipping" }
    s3_bucket     = { S = aws_s3_bucket.workspace.id }
    s3_key        = { S = "public/faq/shipping.md" }
    title         = { S = "Shipping FAQ" }
    content_type  = { S = "text/markdown" }
    required_role = { S = "public" }
  })
}

resource "aws_dynamodb_table_item" "catalog_manual_size" {
  table_name = aws_dynamodb_table.document_catalog.name
  hash_key   = aws_dynamodb_table.document_catalog.hash_key

  item = jsonencode({
    document_id   = { S = "manual/size-guide" }
    s3_bucket     = { S = aws_s3_bucket.workspace.id }
    s3_key        = { S = "public/manual/size-guide.md" }
    title         = { S = "Size Guide" }
    content_type  = { S = "text/markdown" }
    required_role = { S = "public" }
  })
}

# Protected customer export entry (the scenario goal).
resource "aws_dynamodb_table_item" "catalog_customer_export" {
  table_name = aws_dynamodb_table.document_catalog.name
  hash_key   = aws_dynamodb_table.document_catalog.hash_key

  item = jsonencode({
    document_id   = { S = local.customer_export_doc_id }
    s3_bucket     = { S = aws_s3_bucket.workspace.id }
    s3_key        = { S = local.customer_export_s3_key }
    title         = { S = "VIP customer export - 2026-04" }
    content_type  = { S = "text/csv" }
    required_role = { S = local.cognito_groups.seller_admin }
  })
}
