locals {
  flag_secret_string = jsonencode({
    flag          = var.flag_value
    message       = "Congratulations. The dam has broken."
    internal_note = "The build succeeded. The logs are clean. Nobody noticed."
    git_status    = "nothing to commit, working tree clean"
    build_status  = "BUILD SUCCEEDED"
  })
}

resource "aws_secretsmanager_secret" "flag" {
  name                    = "beaverpay/prod/flag-${local.suffix}"
  description             = "BeaverPay scenario flag"
  recovery_window_in_days = 0

  tags = {
    Name      = "beaverpay/prod/flag"
    DataClass = "secret"
    Type      = "scenario-flag"
  }
}

resource "aws_secretsmanager_secret_version" "flag_version" {
  secret_id     = aws_secretsmanager_secret.flag.id
  secret_string = local.flag_secret_string
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "beaverpay/prod/db-master-credentials-${local.suffix}"
  description             = "BeaverPay production DB master credentials"
  recovery_window_in_days = 0

  tags = {
    Name      = "beaverpay/prod/db-master-credentials"
    DataClass = "confidential"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "beaverpay_admin"
    password = "Sup3rS3cur3DB!2024"
    host     = "beaverpay-prod-db.cluster-xxx.us-east-1.rds.amazonaws.com"
    port     = 5432
    dbname   = "beaverpay_prod"
  })
}

resource "aws_secretsmanager_secret" "payment_gateway_key" {
  name                    = "beaverpay/prod/payment-gateway-api-key-${local.suffix}"
  description             = "BeaverPay payment gateway API key"
  recovery_window_in_days = 0

  tags = {
    Name      = "beaverpay/prod/payment-gateway-api-key"
    DataClass = "confidential"
  }
}

resource "aws_secretsmanager_secret_version" "payment_gateway_key_version" {
  secret_id = aws_secretsmanager_secret.payment_gateway_key.id
  secret_string = jsonencode({
    api_key    = "pgw_live_xK9mQ2abcXYZ123456789"
    api_secret = "pgw_secret_aBcDeFgHiJkLmNoPqRsT"
    endpoint   = "https://api.payment-gateway.io/v2"
  })
}
