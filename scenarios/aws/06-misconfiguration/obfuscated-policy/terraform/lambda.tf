#---------------------------------------
# Detection Lambda
#---------------------------------------
resource "aws_cloudwatch_log_group" "detector" {
  name              = "/aws/lambda/${local.detector_lambda_name}"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_lambda_function" "detector" {
  function_name    = local.detector_lambda_name
  role             = aws_iam_role.detector_lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.detector_lambda.output_path
  source_code_hash = data.archive_file.detector_lambda.output_base64sha256

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.detector_basic,
    aws_iam_role_policy.detector_iam,
    aws_cloudwatch_log_group.detector,
  ]
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_events.arn
}
