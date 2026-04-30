resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-cicd-eic"

  # Resource naming
  vpc_name            = "${local.scenario_name}-vpc-${local.scenario_id}"
  igw_name            = "${local.scenario_name}-igw-${local.scenario_id}"
  public_subnet_name  = "${local.scenario_name}-public-subnet-${local.scenario_id}"
  private_subnet_name = "${local.scenario_name}-private-subnet-${local.scenario_id}"
  public_rt_name      = "${local.scenario_name}-public-rt-${local.scenario_id}"
  private_rt_name     = "${local.scenario_name}-private-rt-${local.scenario_id}"
  gitlab_sg_name      = "${local.scenario_name}-gitlab-sg-${local.scenario_id}"
  bastion_sg_name     = "${local.scenario_name}-bastion-sg-${local.scenario_id}"
  target_sg_name      = "${local.scenario_name}-target-sg-${local.scenario_id}"
  gitlab_name         = "${local.scenario_name}-gitlab-server-${local.scenario_id}"
  atlantis_name       = "${local.scenario_name}-atlantis-runner-${local.scenario_id}"
  bastion_name        = "${local.scenario_name}-bastion-host-${local.scenario_id}"
  target_name         = "${local.scenario_name}-target-server-${local.scenario_id}"
  target_key_name     = "${local.scenario_name}-target-key-${local.scenario_id}"
  gitlab_role_name    = "${local.scenario_name}-gitlab-role-${local.scenario_id}"
  atlantis_role_name  = "${local.scenario_name}-atlantis-role-${local.scenario_id}"
  target_role_name    = "${local.scenario_name}-target-role-${local.scenario_id}"
  ssm_param_name      = "/${local.scenario_name}-${local.scenario_id}/atlantis-gitlab-token"

  # Fixed private IPs (eliminate circular dependencies in user_data)
  gitlab_private_ip   = "10.0.1.20"
  atlantis_private_ip = "10.0.1.10"

  # IP whitelist: auto-detect or manual
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Common tags
  common_tags = {
    Scenario    = "cicd-eic-pivot"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }
}
