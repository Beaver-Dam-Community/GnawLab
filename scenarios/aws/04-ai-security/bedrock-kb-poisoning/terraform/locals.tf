// Per-deployment random suffix used in every globally / regionally unique
// resource name (S3 bucket, OpenSearch collection, IAM role, KMS alias, ...).
//
// - Stable inside a single Terraform state, so re-`apply` after partial failure
//   keeps existing resources and does not try to recreate them.
// - A fresh `terraform init` directory always gets a new id, so the same
//   AWS account/region can host multiple parallel deployments of this
//   scenario without name collisions.
// - No `keepers {}` on purpose: nothing should ever force a regeneration of
//   this id while the stack is alive.
resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-bkp"

  # Resource naming convention (matches s3-data-heist / secrets-extraction):
  #   "${scenario_name}-<resource>-${scenario_id}"
  # Length budget: scenario_name = 11 chars, scenario_id = 8 chars, dashes = 2,
  # which leaves up to 32 - 11 - 8 - 2 = 11 chars for <resource> when the
  # underlying service caps the total at 32 (OpenSearch Serverless).
  oss_collection = "${local.scenario_name}-kb-${local.scenario_id}"

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
