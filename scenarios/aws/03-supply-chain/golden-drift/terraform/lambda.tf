#---------------------------------------
# CloudWatch Log Group for the Lambda
#
# Explicit log group lets us set retention. AWSLambdaBasicExecutionRole
# would create one implicitly otherwise, but with no retention configured.
#---------------------------------------
resource "aws_cloudwatch_log_group" "golden_updater" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7

  tags = local.common_tags
}

#---------------------------------------
# Vulnerable Lambda — "golden AMI updater"
#
# This Lambda automates what AWS recommends doing manually: keep the SSM
# parameter that the Launch Template references pointing at the latest
# golden AMI. The vulnerability is that its describe_images call omits the
# Owners filter, so any public AMI whose name matches the configured
# prefix can be returned and selected as "latest".
#
# AMI_NAME_PREFIX is the per-deployment unique prefix derived from the
# scenario_id, so participants must register their malicious AMI under
# the exact name pattern of THIS deployment in order for the Lambda to
# pick it up. This prevents cross-pollution between concurrent lab runs.
#---------------------------------------
resource "aws_lambda_function" "golden_updater" {
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.golden_updater_lambda.output_path
  source_code_hash = data.archive_file.golden_updater_lambda.output_base64sha256

  environment {
    variables = {
      AMI_NAME_PREFIX    = local.ami_name_prefix
      SSM_PARAMETER_NAME = local.ssm_parameter_name
    }
  }

  tags = merge(local.common_tags, {
    Name = local.lambda_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_logs,
    aws_iam_role_policy.lambda_updater,
    aws_cloudwatch_log_group.golden_updater,
  ]
}

#---------------------------------------
# EventBridge schedule — runs the Lambda every minute
#
# rate(1 minute) is intentionally aggressive for lab pacing. In real
# operations this would be hourly or daily.
#---------------------------------------
resource "aws_cloudwatch_event_rule" "golden_updater_schedule" {
  name                = local.eventbridge_rule
  description         = "Trigger golden-updater Lambda every minute"
  schedule_expression = "rate(1 minute)"
  state               = "ENABLED"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "golden_updater" {
  rule      = aws_cloudwatch_event_rule.golden_updater_schedule.name
  target_id = "golden-updater-lambda"
  arn       = aws_lambda_function.golden_updater.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.golden_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.golden_updater_schedule.arn
}
