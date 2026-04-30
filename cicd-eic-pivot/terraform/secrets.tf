resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

# Placeholder updated by GitLab's user_data after the token is generated
resource "aws_ssm_parameter" "atlantis_gitlab_token" {
  name  = local.ssm_param_name
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}
