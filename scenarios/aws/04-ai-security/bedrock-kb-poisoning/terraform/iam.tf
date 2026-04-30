# ============================================================
# Trust policies + Lambda execution roles + Bedrock service roles.
# ============================================================

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ------------------------------------------------------------
# chat_backend
# ------------------------------------------------------------
resource "aws_iam_role" "chat_backend" {
  name               = "${local.scenario_name}-chat-backend-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "chat_backend_basic" {
  role       = aws_iam_role.chat_backend.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "chat_backend_inline" {
  name = "chat-backend-inline"
  role = aws_iam_role.chat_backend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # InvokeAgent scoped to a specific agent alias ARN. Wildcard alias
        # (the v11 mistake) is intentionally avoided.
        Sid      = "InvokeOnlyProdAgentAlias"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = aws_bedrockagent_agent_alias.prod.agent_alias_arn
      },
      {
        Sid      = "InvokeSourceLinkIssuer"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.source_link_issuer.arn
      },
    ]
  })
}

# ------------------------------------------------------------
# source_link_issuer
# ------------------------------------------------------------
resource "aws_iam_role" "source_link_issuer" {
  name               = "${local.scenario_name}-source-link-issuer-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "source_link_issuer_basic" {
  role       = aws_iam_role.source_link_issuer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "source_link_issuer_inline" {
  name = "source-link-issuer-inline"
  role = aws_iam_role.source_link_issuer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Integrated link issuer for both public and seller_admin docs ->
        # bucket-wide GetObject is the design (the security boundary is
        # in source_link_issuer code, currently missing).
        Sid      = "WorkspaceGetObject"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.workspace.arn}/*"
      },
      {
        Sid      = "CatalogLookup"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.document_catalog.arn
      },
    ]
  })
}

# ------------------------------------------------------------
# kb_ingestion_trigger
# ------------------------------------------------------------
resource "aws_iam_role" "kb_ingestion_trigger" {
  name               = "${local.scenario_name}-kb-ingestion-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "kb_ingestion_basic" {
  role       = aws_iam_role.kb_ingestion_trigger.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "kb_ingestion_inline" {
  name = "kb-ingestion-inline"
  role = aws_iam_role.kb_ingestion_trigger.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartIngestionJob"
        Effect = "Allow"
        Action = ["bedrock:StartIngestionJob"]
        Resource = [
          aws_bedrockagent_knowledge_base.main.arn,
          "${aws_bedrockagent_knowledge_base.main.arn}/data-source/*",
        ]
      },
    ]
  })
}

# ------------------------------------------------------------
# Cognito hooks
# ------------------------------------------------------------
resource "aws_iam_role" "cognito_pre_signup" {
  name               = "${local.scenario_name}-cognito-pre-signup-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "cognito_pre_signup_basic" {
  role       = aws_iam_role.cognito_pre_signup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "cognito_post_confirmation" {
  name               = "${local.scenario_name}-cognito-post-conf-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "cognito_post_confirmation_basic" {
  role       = aws_iam_role.cognito_post_confirmation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "cognito_post_confirmation_inline" {
  name = "post-confirmation-inline"
  role = aws_iam_role.cognito_post_confirmation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AddUserToGroup"
        Effect   = "Allow"
        Action   = ["cognito-idp:AdminAddUserToGroup"]
        Resource = aws_cognito_user_pool.main.arn
      },
    ]
  })
}

# ------------------------------------------------------------
# Bedrock Agent execution role
# ------------------------------------------------------------
data "aws_iam_policy_document" "bedrock_agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "bedrock_agent" {
  name               = "${local.scenario_name}-bedrock-agent-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_assume.json
}

resource "aws_iam_role_policy" "bedrock_agent_inline" {
  name = "bedrock-agent-inline"
  role = aws_iam_role.bedrock_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeFoundationModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${var.agent_model_id}"
      },
      {
        Sid    = "RetrieveKB"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = aws_bedrockagent_knowledge_base.main.arn
      },
      {
        Sid      = "ApplyGuardrail"
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = aws_bedrock_guardrail.main.guardrail_arn
      },
    ]
  })
}

# ------------------------------------------------------------
# Bedrock KB execution role
# ------------------------------------------------------------
data "aws_iam_policy_document" "bedrock_kb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${local.scenario_name}-bedrock-kb-${local.scenario_id}"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume.json
}

resource "aws_iam_role_policy" "bedrock_kb_inline" {
  name = "bedrock-kb-inline"
  role = aws_iam_role.bedrock_kb.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeEmbeddingModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"
      },
      {
        Sid      = "OpenSearchAccess"
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = aws_opensearchserverless_collection.kb.arn
      },
      {
        # KB only needs to read public/ for ingestion.
        Sid    = "PublicSourceRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.workspace.arn,
          "${aws_s3_bucket.workspace.arn}/public/*",
        ]
      },
    ]
  })
}
