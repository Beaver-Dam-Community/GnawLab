resource "aws_cognito_user_pool" "developer_portal_userpool" {
  name = "${local.name}-developer-portal-${local.suffix}"

  mfa_configuration = "OFF"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  auto_verified_attributes = ["email"]

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
  }

  tags = {
    Name = "${local.name}-developer-portal-userpool-${local.suffix}"
    Role = "collaborator-auth"
  }
}

resource "aws_cognito_user_pool_client" "portal_client" {
  name         = "${local.name}-portal-client-${local.suffix}"
  user_pool_id = aws_cognito_user_pool.developer_portal_userpool.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  generate_secret = false
}

resource "aws_cognito_user" "ottercode_developer" {
  user_pool_id = aws_cognito_user_pool.developer_portal_userpool.id
  username     = "j.park@ottercode.kr"

  attributes = {
    email          = "j.park@ottercode.kr"
    email_verified = "true"
  }

  password       = "Otter2022!"
  message_action = "SUPPRESS"
  enabled        = true
}

resource "aws_cognito_identity_pool" "developer_identity_pool" {
  identity_pool_name               = "${local.name}-developer-identity-pool-${local.suffix}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.portal_client.id
    provider_name           = aws_cognito_user_pool.developer_portal_userpool.endpoint
    server_side_token_check = false
  }

  tags = {
    Name = "${local.name}-developer-identity-pool-${local.suffix}"
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "identity_pool_roles" {
  identity_pool_id = aws_cognito_identity_pool.developer_identity_pool.id

  roles = {
    "authenticated" = aws_iam_role.collaborator_developer_role.arn
  }
}
