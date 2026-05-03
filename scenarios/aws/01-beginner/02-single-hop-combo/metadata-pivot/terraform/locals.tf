resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-metapivot"

  # Resource naming
  vpc_name              = "${local.scenario_name}-vpc-${local.scenario_id}"
  ec2_name              = "${local.scenario_name}-web-${local.scenario_id}"
  iam_role_name         = "${local.scenario_name}-role-${local.scenario_id}"
  instance_profile_name = "${local.scenario_name}-profile-${local.scenario_id}"
  s3_bucket_name        = "${local.scenario_name}-data-${local.scenario_id}"
  sg_name               = "${local.scenario_name}-sg-${local.scenario_id}"

  # IP whitelist: use provided or auto-detected
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Common tags for all resources
  common_tags = {
    Scenario    = "metadata-pivot"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }
}
