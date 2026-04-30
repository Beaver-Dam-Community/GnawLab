resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

# Placeholder updated by GitLab's user_data after the token is generated
resource "aws_ssm_parameter" "atlantis_gitlab_token" {
  name  = "/${var.scenario_name}-${var.beaver_id}/atlantis-gitlab-token"
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

locals {
  # Fixed private IPs eliminate circular dependencies between GitLab and Atlantis user_data
  gitlab_private_ip   = "10.0.1.20"
  atlantis_private_ip = "10.0.1.10"
}
