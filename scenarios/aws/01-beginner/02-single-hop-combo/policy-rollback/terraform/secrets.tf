#---------------------------------------
# Secrets Manager Secret (FLAG)
#---------------------------------------
resource "aws_secretsmanager_secret" "flag" {
  name        = local.secret_name
  description = "Production database credentials - Beaver Dam Industries"

  # Force delete without recovery window for easy cleanup
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name        = local.secret_name
    Environment = "production"
    Application = "BeaverDamIndustries"
  })
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id = aws_secretsmanager_secret.flag.id

  secret_string = jsonencode({
    flag = var.flag_value
  })
}
