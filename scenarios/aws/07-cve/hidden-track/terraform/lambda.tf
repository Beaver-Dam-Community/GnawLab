resource "aws_lambda_layer_version" "exiftool" {
  layer_name          = local.lambda_layer_name
  filename            = "${path.module}/exiftool-layer.zip"
  compatible_runtimes = ["python3.9"]
  description         = "ExifTool 12.23 — unpatched, CVE-2021-22204 affected"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "process_upload" {
  function_name    = local.lambda_function_name
  role             = aws_iam_role.lambda_exec.arn
  runtime          = "python3.9"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  layers = [aws_lambda_layer_version.exiftool.arn]

  environment {
    variables = {
      VAULT_BUCKET   = aws_s3_bucket.vault.id
      UPLOADS_BUCKET = aws_s3_bucket.uploads.id
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Processes artist uploads with ExifTool 12.23 metadata extraction"
  })

  depends_on = [aws_iam_role_policy.lambda_exec_policy]
}
