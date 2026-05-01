# CloudFront distribution for the SaaS console + customer widget,
# protected by a WAFv2 web ACL whose IP set matches local.cg_whitelist_list.

# ------------------------------------------------------------
# WAFv2 IP allow list. Must live in us-east-1 for CloudFront.
# ------------------------------------------------------------
resource "aws_wafv2_ip_set" "console" {
  name               = "${local.scenario_name}-console-ipset-${local.scenario_id}"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = local.cg_whitelist_list
}

resource "aws_wafv2_web_acl" "console" {
  name  = "${local.scenario_name}-console-acl-${local.scenario_id}"
  scope = "CLOUDFRONT"

  default_action {
    block {}
  }

  rule {
    name     = "AllowWhitelistedIPs"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.console.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowWhitelistedIPs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.scenario_name}-console-acl-${local.scenario_id}"
    sampled_requests_enabled   = true
  }
}

# ------------------------------------------------------------
# CloudFront distribution: console (S3 origin) + /api/* (API GW origin).
# ------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "console" {
  name                              = "${local.scenario_name}-console-oac-${local.scenario_id}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "console" {
  enabled             = true
  default_root_object = "index.html"
  is_ipv6_enabled     = true
  comment             = "TokTok-Support console (${local.scenario_id})"
  web_acl_id          = aws_wafv2_web_acl.console.arn
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.console.bucket_regional_domain_name
    origin_id                = "console-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.console.id
  }

  origin {
    domain_name = "${aws_api_gateway_rest_api.main.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "chat-api"
    origin_path = "/${aws_api_gateway_stage.prod.stage_name}"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "console-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
    compress    = true
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "chat-api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type"]
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}
