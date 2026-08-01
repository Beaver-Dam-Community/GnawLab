# document_catalog maps opaque catalog IDs to S3 objects and required groups.
# Both public FAQ links and the seller_admin-only customer export flow through
# one internal Lambda. Direct downloads enforce `required_role`; chat citation
# links intentionally omit that final caller authorization check.

resource "aws_dynamodb_table" "document_catalog" {
  name         = "${local.scenario_name}-document-catalog-${local.scenario_id}"
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
    document_id   = { S = local.catalog_ids.refund }
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
    document_id   = { S = local.catalog_ids.exchange }
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
    document_id   = { S = local.catalog_ids.shipping }
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
    document_id   = { S = local.catalog_ids.size_guide }
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
    created_at    = { S = "2026-04-30" }
    row_count     = { S = "50" }
    display_size  = { S = "12.4 KB" }
  })
}
