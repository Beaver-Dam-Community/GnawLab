# Auto-detect public IP for whitelisting
data "http" "my_ip" {
  url = "https://ifconfig.co/ip"

  request_headers = {
    Accept = "text/plain"
  }
}

# Current AWS account information
data "aws_caller_identity" "current" {}

# Current region
data "aws_region" "current" {}

# Available AZs for subnet placement
data "aws_availability_zones" "available" {
  state = "available"
}
