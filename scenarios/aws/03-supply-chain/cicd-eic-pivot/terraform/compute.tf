data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "tls_private_key" "target_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "target_key_pair" {
  key_name   = local.target_key_name
  public_key = tls_private_key.target_key.public_key_openssh
}

resource "aws_security_group" "gitlab_sg" {
  name        = local.gitlab_sg_name
  description = "Allow HTTP and SSH from whitelist for GitLab"
  vpc_id      = aws_vpc.scenario_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  # Allow Atlantis runner to call GitLab API internally
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = local.gitlab_sg_name })
}

resource "aws_security_group" "bastion_sg" {
  name        = local.bastion_sg_name
  description = "Allow SSH from whitelist, Atlantis webhook from GitLab"
  vpc_id      = aws_vpc.scenario_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  # Allow GitLab to deliver webhooks to Atlantis
  ingress {
    from_port       = 4141
    to_port         = 4141
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = local.bastion_sg_name })
}

resource "aws_security_group" "atlantis_sg" {
  name        = local.atlantis_sg_name
  description = "Allow SSH from whitelist and webhooks from GitLab"
  vpc_id      = aws_vpc.scenario_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  # Allow GitLab to deliver webhooks to Atlantis
  ingress {
    from_port       = 4141
    to_port         = 4141
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = local.atlantis_sg_name })
}

resource "aws_security_group" "target_sg" {
  name        = local.target_sg_name
  description = "Allow SSH only from Bastion security group"
  vpc_id      = aws_vpc.scenario_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = local.target_sg_name })
}

resource "aws_instance" "gitlab_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.public_subnet.id
  private_ip             = local.gitlab_private_ip
  iam_instance_profile   = aws_iam_instance_profile.gitlab_profile.name
  vpc_security_group_ids = [aws_security_group.gitlab_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup-gitlab.sh.tpl", {
    region              = var.region
    atlantis_private_ip = local.atlantis_private_ip
    webhook_secret      = random_password.webhook_secret.result
    ssm_token_path      = local.ssm_param_name
    setup_bucket        = aws_s3_bucket.setup_files.bucket
  }))

  depends_on = [
    aws_s3_object.infra_main_tf,
    aws_s3_object.infra_variables_tf,
    aws_s3_object.infra_atlantis_yaml,
    aws_s3_object.infra_security_review,
    aws_s3_object.infra_adr_deploy,
    aws_s3_object.infra_slack_export,
    aws_s3_object.infra_readme,
    aws_s3_object.infra_incident_2024_02,
    aws_s3_object.infra_env_example,
  ]

  tags = merge(local.common_tags, { Name = local.gitlab_name })
}

resource "aws_instance" "atlantis_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  private_ip             = local.atlantis_private_ip
  iam_instance_profile   = aws_iam_instance_profile.atlantis_profile.name
  vpc_security_group_ids = [aws_security_group.atlantis_sg.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup-atlantis.sh.tpl", {
    region            = var.region
    gitlab_private_ip = local.gitlab_private_ip
    webhook_secret    = random_password.webhook_secret.result
    ssm_token_path    = local.ssm_param_name
  }))

  tags = merge(local.common_tags, { Name = local.atlantis_name })
}

# NOTE: EIC attack path requires ec2-instance-connect package on this host.
# Ubuntu 22.04 AMIs include it by default. If the AMI changes, add:
#   apt-get install -y ec2-instance-connect
# to user_data below.
resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
              #!/bin/bash
              chmod -x /etc/update-motd.d/* 2>/dev/null || true
              printf '%s\n' \
                'BeaverOps Internal Infrastructure' \
                '----------------------------------' \
                '' \
                '       ___' \
                '      /   \' \
                '     | ^ ^ |' \
                '     | --- |' \
                '      \___/' \
                '     /|   |\' \
                '    / |   | \' \
                '   /__|___|__\' \
                '      |   |' \
                '     =======' \
                '' \
                '  Authorized access only.' \
                '  All activity is monitored.' \
                '' > /etc/motd
              # app-prod deploy key - pre-EIC legacy; PLAT-1203 tracks removal
              echo "${tls_private_key.target_key.private_key_pem}" > /home/ubuntu/target-key.pem
              chown ubuntu:ubuntu /home/ubuntu/target-key.pem
              chmod 400 /home/ubuntu/target-key.pem
              EOF

  tags = merge(local.common_tags, { Name = local.bastion_name })
}

resource "aws_instance" "target_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  key_name               = aws_key_pair.target_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.target_profile.name
  vpc_security_group_ids = [aws_security_group.target_sg.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
              #!/bin/bash
              chmod -x /etc/update-motd.d/* 2>/dev/null || true
              printf '%s\n' \
                'BeaverOps Production Server' \
                '-----------------------------' \
                '' \
                '  Keep it safe. Keep it simple.' \
                '' > /etc/motd
              mkdir -p /home/ubuntu/.ssh
              echo "${tls_private_key.target_key.public_key_openssh}" >> /home/ubuntu/.ssh/authorized_keys
              chown -R ubuntu:ubuntu /home/ubuntu/.ssh
              chmod 700 /home/ubuntu/.ssh
              chmod 600 /home/ubuntu/.ssh/authorized_keys
              echo "FLAG{SUPPLY_CHAIN_EIC_SUCCESS_$(openssl rand -hex 8)}" > /home/ubuntu/flag.txt
              chown ubuntu:ubuntu /home/ubuntu/flag.txt
              chmod 444 /home/ubuntu/flag.txt
              EOF

  tags = merge(local.common_tags, { Name = local.target_name })
}
