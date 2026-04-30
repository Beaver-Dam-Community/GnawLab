# Single SSE-KMS key used for the workspace bucket (public + admin-only objects).
# Sharing one key across prefixes is operationally convenient for a small SaaS;
# the security boundary in this scenario is *code-level* permission re-check
# inside source_link_issuer, NOT KMS prefix-condition policy.

resource "aws_kms_key" "workspace" {
  description             = "TokTok workspace bucket SSE-KMS (${local.scenario_id})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # The Lambdas that legitimately read or write workspace objects need
        # plain Decrypt/GenerateDataKey on this key.
        Sid    = "AllowServiceLambdas"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.chat_backend.arn,
            aws_iam_role.source_link_issuer.arn,
            aws_iam_role.kb_ingestion_trigger.arn,
            aws_iam_role.bedrock_kb.arn,
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "workspace" {
  name          = "alias/${local.name_prefix}-workspace"
  target_key_id = aws_kms_key.workspace.key_id
}
