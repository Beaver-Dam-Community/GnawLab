resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-watchdog"

  # Resource names with unique suffix
  codecommit_repo_name = "${local.scenario_name}-config-${local.scenario_id}"
  log_group_name       = "/corp/deploy-pipeline-${local.scenario_id}"
  ecr_repo_name        = "${local.scenario_name}-app-${local.scenario_id}"

  # ARNs for IAM policy documents
  codecommit_repo_arn = "arn:aws:codecommit:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.codecommit_repo_name}"
  log_group_arn       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"
  ecr_repo_arn        = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_repo_name}"
  s3_artifact_arn     = aws_s3_bucket.artifacts.arn
}
