resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-rollback"

  # Resource naming: {scenario_name}-{resource}-{scenario_id}
  iam_user_name   = "${local.scenario_name}-user-${local.scenario_id}"
  iam_policy_name = "${local.scenario_name}-policy-${local.scenario_id}"
  secret_name     = "${local.scenario_name}-secret-${local.scenario_id}"

  # IP whitelist: use provided or auto-detected
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Common tags for all resources
  common_tags = {
    Scenario    = "policy-rollback"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }
}
