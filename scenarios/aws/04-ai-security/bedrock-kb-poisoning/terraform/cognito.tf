# Cognito User Pool with self-signup, auto-confirm and auto-group hooks.
# Domain-based auto-grouping: BPO emails -> bpo_editor; seller emails -> seller_admin.

resource "aws_cognito_user_pool" "main" {
  name = "${local.scenario_name}-pool-${local.scenario_id}"

  # Allow self-signup. Email is the username + verification channel.
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  lambda_config {
    pre_sign_up       = aws_lambda_function.cognito_pre_signup.arn
    post_confirmation = aws_lambda_function.cognito_post_confirmation.arn
  }
}

# Cognito User Pool Client used by the SaaS console SPA + customer widget.
# No client secret (browser SPA).
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.scenario_name}-spa-${local.scenario_id}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# Permission for Cognito User Pool to invoke the pre/post hooks.
resource "aws_lambda_permission" "cognito_pre_signup" {
  statement_id  = "AllowCognitoPreSignup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognito_pre_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_lambda_permission" "cognito_post_confirmation" {
  statement_id  = "AllowCognitoPostConfirmation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognito_post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

# Groups used by the JWT cognito:groups claim.
resource "aws_cognito_user_group" "seller_admin" {
  name         = local.cognito_groups.seller_admin
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Seller workspace owner. Full access including customer exports."
  precedence   = 1
}

resource "aws_cognito_user_group" "seller_manager" {
  name         = local.cognito_groups.seller_manager
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Seller staff. Refunds up to KRW 2,000,000."
  precedence   = 2
}

resource "aws_cognito_user_group" "bpo_editor" {
  name         = local.cognito_groups.bpo_editor
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "BPO outsourced CS staff. FAQ editor + chat QA + masked customer view."
  precedence   = 3
}

# ============================================================
# Pre-seeded scenario users.
# ============================================================
# Random per-cgid passwords. Surfaced via terraform output.

resource "random_password" "kay" {
  length  = 16
  special = false
}

resource "random_password" "owner" {
  length  = 16
  special = false
}

resource "aws_cognito_user" "kay" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.kay_email
  password       = random_password.kay.result
  message_action = "SUPPRESS"

  attributes = {
    email          = var.kay_email
    email_verified = "true"
  }

  # Pre-seeded users go through the same PreSignUp / PostConfirmation
  # hooks that self-signup uses. The lambda:InvokeFunction permissions
  # have to exist before AdminCreateUser fires the hooks, otherwise
  # Cognito returns UnexpectedLambdaException(AccessDeniedException).
  depends_on = [
    aws_lambda_permission.cognito_pre_signup,
    aws_lambda_permission.cognito_post_confirmation,
  ]
}

resource "aws_cognito_user" "owner" {
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = var.owner_email
  password       = random_password.owner.result
  message_action = "SUPPRESS"

  attributes = {
    email          = var.owner_email
    email_verified = "true"
  }

  depends_on = [
    aws_lambda_permission.cognito_pre_signup,
    aws_lambda_permission.cognito_post_confirmation,
  ]
}

resource "aws_cognito_user_in_group" "kay_in_bpo" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.bpo_editor.name
  username     = aws_cognito_user.kay.username
}

resource "aws_cognito_user_in_group" "owner_in_admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.seller_admin.name
  username     = aws_cognito_user.owner.username
}
