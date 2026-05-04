# Auto-detect public IP
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

# Available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
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
}
