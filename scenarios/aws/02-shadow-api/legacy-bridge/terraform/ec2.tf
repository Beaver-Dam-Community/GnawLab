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
  shadow_user_data = templatefile("${path.module}/user_data/shadow_setup.sh.tftpl", {
    app_source = file("${path.module}/../assets/api_v1/app.py")
  })

  gateway_user_data = templatefile("${path.module}/user_data/gateway_setup.sh.tftpl", {
    app_source      = file("${path.module}/../assets/api_v5/app.py")
    index_html      = file("${path.module}/../assets/web/index.html")
    media_data      = file("${path.module}/../assets/seed_data/media_files.json")
    shadow_api_host = aws_instance.shadow_api_ec2.private_ip
  })
}

resource "aws_instance" "shadow_api_ec2" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.shadow_api_subnet.id
  vpc_security_group_ids      = [aws_security_group.shadow_api_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.shadow_api_profile.name
  associate_public_ip_address = false

  user_data                   = local.shadow_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = {
    Name        = "Shadow-API-Server-${local.suffix}"
    Role        = "v1-legacy-api"
    NetworkTier = "private"
  }

  depends_on = [
    aws_nat_gateway.legacy_bridge_natgw,
    aws_iam_role_policy.shadow_api_role_s3_policy,
  ]
}

resource "aws_instance" "public_gateway_ec2" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_gateway_subnet.id
  vpc_security_group_ids      = [aws_security_group.public_gateway_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.gateway_app_profile.name
  associate_public_ip_address = true

  user_data                   = local.gateway_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = {
    Name        = "Public-Gateway-Server-${local.suffix}"
    Role        = "v5-portal"
    NetworkTier = "public"
  }

  depends_on = [aws_instance.shadow_api_ec2]
}