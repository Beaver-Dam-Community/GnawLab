data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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

locals {
  portal_user_data = templatefile("${path.module}/user_data/portal_setup.sh.tftpl", {
    index_html           = file("${path.module}/../assets/web/index.html")
    cognito_pool_id      = aws_cognito_user_pool.developer_portal_userpool.id
    cognito_client_id    = aws_cognito_user_pool_client.portal_client.id
    identity_pool_id     = aws_cognito_identity_pool.developer_identity_pool.id
    region               = var.region
    account_id           = data.aws_caller_identity.current.account_id
  })
}

resource "aws_instance" "portal_ec2" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.portal_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.portal_ec2_profile.name
  associate_public_ip_address = true

  user_data                   = local.portal_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name        = "${local.name}-developer-portal-${local.suffix}"
    Role        = "developer-portal"
    NetworkTier = "public"
  }

  depends_on = [
    aws_cognito_user_pool.developer_portal_userpool,
    aws_cognito_user_pool_client.portal_client,
  ]
}
