data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

data "aws_caller_identity" "current" {}
