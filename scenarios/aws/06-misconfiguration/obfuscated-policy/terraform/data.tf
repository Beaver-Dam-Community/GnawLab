# Auto-detect public IP for whitelisting
data "http" "my_ip" {
  url = "https://ifconfig.co/ip"

  request_headers = {
    Accept = "text/plain"
  }
}

# Current AWS account info
data "aws_caller_identity" "current" {}

# Current region
data "aws_region" "current" {}

# Package the detection Lambda code
data "archive_file" "detector_lambda" {
  type        = "zip"
  output_path = "${path.module}/.build/detector_lambda.zip"

  source {
    content  = local.detector_lambda_code
    filename = "lambda_function.py"
  }
}
