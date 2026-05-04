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
