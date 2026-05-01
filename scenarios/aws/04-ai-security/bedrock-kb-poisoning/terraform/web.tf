# Upload the SaaS console + customer storefront widget assets to the
# console hosting bucket (served behind CloudFront).

# ============================================================
# Console SPA
# ============================================================
resource "aws_s3_object" "console_index" {
  bucket       = aws_s3_bucket.console.id
  key          = "index.html"
  source       = "${path.module}/../assets/web/index.html"
  etag         = filemd5("${path.module}/../assets/web/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "console_styles" {
  bucket       = aws_s3_bucket.console.id
  key          = "styles.css"
  source       = "${path.module}/../assets/web/styles.css"
  etag         = filemd5("${path.module}/../assets/web/styles.css")
  content_type = "text/css"
}

resource "aws_s3_object" "console_app" {
  bucket       = aws_s3_bucket.console.id
  key          = "app.js"
  source       = "${path.module}/../assets/web/app.js"
  etag         = filemd5("${path.module}/../assets/web/app.js")
  content_type = "application/javascript"
}

# Runtime configuration injected by terraform. The console reads
# window.TOKTOK_CONFIG from this script tag.
resource "aws_s3_object" "console_config" {
  bucket       = aws_s3_bucket.console.id
  key          = "config.js"
  content_type = "application/javascript"
  content      = <<-EOT
    window.TOKTOK_CONFIG = {
      cgid: "${local.scenario_id}",
      region: "${var.region}",
      userPoolId: "${aws_cognito_user_pool.main.id}",
      userPoolClientId: "${aws_cognito_user_pool_client.spa.id}",
      chatApiBase: "https://${aws_cloudfront_distribution.console.domain_name}/api",
      bpoDomain: "${var.bpo_email_domain}",
      sellerDomain: "${var.seller_email_domain}",
      customerExportDocId: "${local.customer_export_doc_id}",
      seedDocs: {
        "faq/refund-policy-v3":   ${jsonencode(file("${path.module}/../assets/kb_seed/refund-policy-v3.md"))},
        "faq/exchange-policy-v2": ${jsonencode(file("${path.module}/../assets/kb_seed/exchange-policy-v2.md"))},
        "faq/shipping":           ${jsonencode(file("${path.module}/../assets/kb_seed/shipping-faq.md"))},
        "manual/size-guide":      ${jsonencode(file("${path.module}/../assets/kb_seed/size-guide.md"))}
      }
    };
  EOT
}

# ============================================================
# Customer-facing storefront mockup (FitMall site)
# ============================================================
resource "aws_s3_object" "widget_index" {
  bucket       = aws_s3_bucket.console.id
  key          = "fitmall/index.html"
  source       = "${path.module}/../assets/web/fitmall/index.html"
  etag         = filemd5("${path.module}/../assets/web/fitmall/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "widget_config" {
  bucket       = aws_s3_bucket.console.id
  key          = "fitmall/config.js"
  content_type = "application/javascript"
  content      = <<-EOT
    window.FITMALL_CONFIG = {
      cgid: "${local.scenario_id}",
      consoleHost: "https://${aws_cloudfront_distribution.console.domain_name}/"
    };
  EOT
}
