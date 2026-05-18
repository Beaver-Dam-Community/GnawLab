data "http" "my_ip" {
  url = "https://ifconfig.co/ip"
  request_headers = {
    Accept = "text/plain"
  }
}

data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../assets/lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}
