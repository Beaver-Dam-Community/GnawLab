data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Auto-detect public IP for the WAFv2 + API Gateway whitelist.
data "http" "my_ip" {
  url = "https://ifconfig.co/ip"

  request_headers = {
    Accept = "text/plain"
  }
}
