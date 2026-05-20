#---------------------------------------
# EventBridge Rule - IAM CreatePolicy / AttachUserPolicy
#---------------------------------------
resource "aws_cloudwatch_event_rule" "iam_events" {
  name        = local.eventbridge_rule
  description = "Trigger detection Lambda on IAM CreatePolicy and AttachUserPolicy"

  event_pattern = jsonencode({
    source      = ["aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["iam.amazonaws.com"]
      eventName   = ["CreatePolicy", "AttachUserPolicy"]
    }
  })

  tags = local.common_tags

  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_event_target" "detector" {
  rule      = aws_cloudwatch_event_rule.iam_events.name
  target_id = "detector-lambda"
  arn       = aws_lambda_function.detector.arn
}
