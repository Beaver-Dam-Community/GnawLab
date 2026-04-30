# [Intentional Vulnerability] No KMS key — Prowler detects this as a FAIL
# Participants discover this log group name in the Prowler report,
# then query the log contents directly via Steampipe to obtain Git credentials

resource "aws_cloudwatch_log_group" "deploy_pipeline" {
  name              = "/corp/deploy-pipeline"
  retention_in_days = 90
  # kms_key_id not set — intentional vulnerability (no KMS encryption)

  tags = {
    Name     = "deploy-pipeline-logs"
    Scenario = "${var.project_name}-deploy-hijack"
    Vuln     = "no-kms-encryption"
  }
}
