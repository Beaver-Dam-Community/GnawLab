resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

# Opaque suffix appended inside FLAG{...} so the literal flag value can't
# be guessed from the scenario name or walkthrough hints, and so two
# concurrent deployments never share a flag.
resource "random_string" "flag_suffix" {
  length  = 16
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-codejudge"

  # var.flag_value default = "FLAG{pickle_to_docker_sock_to_imds_to_ecs_exec}"
  # → become            "FLAG{pickle_to_docker_sock_to_imds_to_ecs_exec_<16 hex>}"
  flag_value = replace(var.flag_value, "}", "_${random_string.flag_suffix.result}}")

  # Resource naming convention: {scenario_name}-{role}-{scenario_id}
  vpc_name              = "${local.scenario_name}-vpc-${local.scenario_id}"
  igw_name              = "${local.scenario_name}-igw-${local.scenario_id}"
  nat_name              = "${local.scenario_name}-nat-${local.scenario_id}"
  public_subnet_name    = "${local.scenario_name}-public-${local.scenario_id}"
  private_subnet_a_name = "${local.scenario_name}-private-a-${local.scenario_id}"
  private_subnet_b_name = "${local.scenario_name}-private-b-${local.scenario_id}"
  public_rt_name        = "${local.scenario_name}-public-rt-${local.scenario_id}"
  private_rt_name       = "${local.scenario_name}-private-rt-${local.scenario_id}"

  vulnboard_sg_name = "${local.scenario_name}-vulnboard-sg-${local.scenario_id}"
  fargate_sg_name   = "${local.scenario_name}-fargate-sg-${local.scenario_id}"

  ec2_name         = "${local.scenario_name}-vulnboard-${local.scenario_id}"
  app_role_name    = "${local.scenario_name}-app-role-${local.scenario_id}"
  app_profile_name = "${local.scenario_name}-app-profile-${local.scenario_id}"
  task_role_name   = "${local.scenario_name}-task-role-${local.scenario_id}"
  exec_role_name   = "${local.scenario_name}-exec-role-${local.scenario_id}"

  ecs_cluster_name   = "${local.scenario_name}-cluster-${local.scenario_id}"
  ecs_task_family    = "${local.scenario_name}-task-${local.scenario_id}"
  ecs_service_name   = "${local.scenario_name}-service-${local.scenario_id}"
  ecs_log_group_name = "/gnawlab/codejudge/${local.scenario_id}"

  vpc_cidr           = "10.42.0.0/16"
  public_subnet_cidr = "10.42.0.0/24"
  private_a_cidr     = "10.42.10.0/24"
  private_b_cidr     = "10.42.11.0/24"

  # IP whitelist: explicit override or auto-detect from ifconfig.co
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    app_py     = file("${path.module}/templates/app.py")
    dockerfile = file("${path.module}/templates/Dockerfile")
    compose    = file("${path.module}/templates/docker-compose.yml")
  })
}
