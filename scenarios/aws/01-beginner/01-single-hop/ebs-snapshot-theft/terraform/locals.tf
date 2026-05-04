resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-ebstheft"

  # Resource naming
  iam_user_name   = "${local.scenario_name}-user-${local.scenario_id}"
  iam_policy_name = "${local.scenario_name}-policy-${local.scenario_id}"
  vpc_name        = "${local.scenario_name}-vpc-${local.scenario_id}"
  subnet_name     = "${local.scenario_name}-subnet-${local.scenario_id}"
  igw_name        = "${local.scenario_name}-igw-${local.scenario_id}"
  sg_name         = "${local.scenario_name}-sg-${local.scenario_id}"
  instance_name   = "${local.scenario_name}-source-${local.scenario_id}"
  volume_name     = "${local.scenario_name}-data-${local.scenario_id}"
  snapshot_name   = "${local.scenario_name}-backup-${local.scenario_id}"
  key_name        = "${local.scenario_name}-key-${local.scenario_id}"

  # IP whitelist: use provided or auto-detected
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Use first available AZ
  availability_zone = data.aws_availability_zones.available.names[0]

  # Common tags for all resources
  common_tags = {
    Scenario    = "ebs-snapshot-theft"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }
}
