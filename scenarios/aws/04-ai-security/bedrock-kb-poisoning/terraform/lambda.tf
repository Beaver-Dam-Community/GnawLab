# Lambda packaging + functions.
# All five Lambdas use Python 3.12 with no extra dependencies (everything
# they import is available in the AWS Lambda Python 3.12 runtime).

# ------------------------------------------------------------
# Packaging
# ------------------------------------------------------------
data "archive_file" "cognito_pre_signup" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_source/cognito_pre_signup"
  output_path = "${path.module}/.build/cognito_pre_signup.zip"
}

data "archive_file" "cognito_post_confirmation" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_source/cognito_post_confirmation"
  output_path = "${path.module}/.build/cognito_post_confirmation.zip"
}

data "archive_file" "kb_ingestion_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_source/kb_ingestion_trigger"
  output_path = "${path.module}/.build/kb_ingestion_trigger.zip"
}

data "archive_file" "chat_backend" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_source/chat_backend"
  output_path = "${path.module}/.build/chat_backend.zip"
}

data "archive_file" "source_link_issuer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_source/source_link_issuer"
  output_path = "${path.module}/.build/source_link_issuer.zip"
}

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------
resource "aws_lambda_function" "cognito_pre_signup" {
  function_name    = "${local.scenario_name}-cognito-pre-signup-${local.scenario_id}"
  filename         = data.archive_file.cognito_pre_signup.output_path
  source_code_hash = data.archive_file.cognito_pre_signup.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.cognito_pre_signup.arn
  timeout          = 5

  environment {
    variables = {
      BPO_DOMAIN    = var.bpo_email_domain
      SELLER_DOMAIN = var.seller_email_domain
    }
  }
}

resource "aws_lambda_function" "cognito_post_confirmation" {
  function_name    = "${local.scenario_name}-cognito-post-conf-${local.scenario_id}"
  filename         = data.archive_file.cognito_post_confirmation.output_path
  source_code_hash = data.archive_file.cognito_post_confirmation.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.cognito_post_confirmation.arn
  timeout          = 5

  environment {
    variables = {
      BPO_DOMAIN    = var.bpo_email_domain
      SELLER_DOMAIN = var.seller_email_domain
    }
  }
}

resource "aws_lambda_function" "kb_ingestion_trigger" {
  function_name    = "${local.scenario_name}-kb-ingestion-${local.scenario_id}"
  filename         = data.archive_file.kb_ingestion_trigger.output_path
  source_code_hash = data.archive_file.kb_ingestion_trigger.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.kb_ingestion_trigger.arn
  timeout          = 30

  environment {
    variables = {
      KB_ID          = aws_bedrockagent_knowledge_base.main.id
      DATA_SOURCE_ID = aws_bedrockagent_data_source.public_prefix.data_source_id
    }
  }
}

resource "aws_lambda_function" "source_link_issuer" {
  function_name    = "${local.scenario_name}-source-link-issuer-${local.scenario_id}"
  filename         = data.archive_file.source_link_issuer.output_path
  source_code_hash = data.archive_file.source_link_issuer.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.source_link_issuer.arn
  timeout          = 10

  environment {
    variables = {
      CATALOG_TABLE   = aws_dynamodb_table.document_catalog.name
      URL_TTL_SECONDS = "300"
    }
  }
}

resource "aws_lambda_function" "chat_backend" {
  function_name    = "${local.scenario_name}-chat-backend-${local.scenario_id}"
  filename         = data.archive_file.chat_backend.output_path
  source_code_hash = data.archive_file.chat_backend.output_base64sha256
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.chat_backend.arn
  timeout          = 60

  environment {
    variables = {
      AGENT_ID               = aws_bedrockagent_agent.main.agent_id
      AGENT_ALIAS_ID         = aws_bedrockagent_agent_alias.prod.agent_alias_id
      SOURCE_LINK_ISSUER_ARN = aws_lambda_function.source_link_issuer.arn
    }
  }
}

# ------------------------------------------------------------
# Permissions
# ------------------------------------------------------------
resource "aws_lambda_permission" "kb_ingestion_trigger_s3" {
  statement_id  = "AllowS3InvokeIngestion"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_ingestion_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.workspace.arn
}
