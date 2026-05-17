# Auto-detect public IP for ALB whitelist
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

# Available AZs for subnet placement
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI for AMI baking base
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Package the detection / golden-ami-updater Lambda code
data "archive_file" "golden_updater_lambda" {
  type        = "zip"
  output_path = "${path.module}/.build/golden_updater_lambda.zip"

  source {
    content  = local.golden_updater_lambda_code
    filename = "lambda_function.py"
  }
}
