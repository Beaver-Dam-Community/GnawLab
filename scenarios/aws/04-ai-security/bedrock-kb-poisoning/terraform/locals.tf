resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-bkp"

  # Resource naming. Most resources reuse `name_prefix`. OpenSearch Serverless
  # collection / access policy / security policy names are capped at 32 chars,
  # so a shorter `oss_*` variant is used there.
  name_prefix    = "${local.scenario_name}-${local.scenario_id}"
  oss_prefix     = "bkp-${local.scenario_id}"
  oss_collection = "bkp-kb-${local.scenario_id}"

  # KB document IDs / S3 keys for the protected April 2026 customer export.
  customer_export_doc_id = "customer-export/fitmall/2026-04"
  customer_export_s3_key = "admin-only/customers/customer-export-2026-04.csv"

  # Cognito group names. Must match the JWT `cognito:groups` claim values
  # referenced by chat_backend / source_link_issuer Lambda code.
  cognito_groups = {
    seller_admin   = "seller_admin"
    seller_manager = "seller_manager"
    bpo_editor     = "bpo_editor"
  }

  # IP whitelist: explicit value wins, otherwise auto-detected /32.
  whitelist_cidr    = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"
  cg_whitelist_list = [local.whitelist_cidr]

  common_tags = {
    Scenario    = "bedrock-kb-poisoning"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }
}
