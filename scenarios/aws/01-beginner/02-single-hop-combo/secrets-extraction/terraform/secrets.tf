# KMS Key for Secrets encryption
resource "aws_kms_key" "secrets" {
  description             = "KMS key for secrets-extraction scenario"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.scenario_name}-kms-${local.scenario_id}"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = local.kms_alias
  target_key_id = aws_kms_key.secrets.key_id
}

# Secrets Manager Secret containing the FLAG
resource "aws_secretsmanager_secret" "flag" {
  name        = local.secret_name
  description = "Production database credentials - DO NOT SHARE"
  kms_key_id  = aws_kms_key.secrets.arn

  # Force delete without recovery window for easy cleanup
  recovery_window_in_days = 0

  tags = {
    Name        = local.secret_name
    Environment = "production"
    Application = "ResizeCloud"
  }
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id = aws_secretsmanager_secret.flag.id

  secret_string = jsonencode({
    db_host     = "prod-db.internal.resizecloud.com"
    db_port     = 5432
    db_name     = "resizecloud_prod"
    db_user     = "admin"
    db_password = "SuperSecretP@ssw0rd!"
    api_key     = "sk-resizecloud-prod-a1b2c3d4e5f6"
    flag        = var.flag_value
  })
}
