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

  user_data = base64encode(templatefile("${path.module}/scripts/setup-gitlab.sh.tpl", {
    region              = var.region
    atlantis_private_ip = local.atlantis_private_ip
    webhook_secret      = random_password.webhook_secret.result
    ssm_token_path      = local.ssm_param_name
    main_tf_b64         = base64encode(file("${path.module}/../assets/infra-repo/main.tf"))
    variables_tf_b64    = base64encode(file("${path.module}/../assets/infra-repo/variables.tf"))
    atlantis_yaml_b64   = base64encode(file("${path.module}/../assets/infra-repo/atlantis.yaml"))
  }))

  tags = merge(local.common_tags, { Name = local.gitlab_name })
}

resource "aws_instance" "atlantis_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  private_ip             = local.atlantis_private_ip
  iam_instance_profile   = aws_iam_instance_profile.atlantis_profile.name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  # IMDSv1 must remain accessible for the scenario exploit path to function
  metadata_options {
    http_tokens = "optional"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/setup-atlantis.sh.tpl", {
    region            = var.region
    gitlab_private_ip = local.gitlab_private_ip
    webhook_secret    = random_password.webhook_secret.result
    ssm_token_path    = local.ssm_param_name
  }))

  tags = merge(local.common_tags, { Name = local.atlantis_name })
}

resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  user_data = <<-EOF
              #!/bin/bash
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

  user_data = <<-EOF
              #!/bin/bash
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
