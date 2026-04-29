# AMI 데이터 소스 (Ubuntu 22.04 LTS)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 1. 공통 보안 그룹: SSH 허용 (Bastion용)
resource "aws_security_group" "bastion_sg" {
  name        = "${var.scenario_name}-bastion-sg-${var.beaver_id}"
  description = "Allow SSH from anywhere (whitelisted)"
  vpc_id      = aws_vpc.scenario_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.cg_whitelist
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. 타겟 보안 그룹: Bastion에서만 접근 허용
resource "aws_security_group" "target_sg" {
  name        = "${var.scenario_name}-target-sg-${var.beaver_id}"
  description = "Allow SSH only from Bastion"
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
}

# 3. Atlantis Runner
resource "aws_instance" "atlantis_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.atlantis_profile.name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "${var.scenario_name}-atlantis-runner-${var.beaver_id}"
  }
}

# 4. Bastion Host
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

  tags = {
    Name = "${var.scenario_name}-bastion-host-${var.beaver_id}"
  }
}

# 5. Target Server
resource "aws_instance" "target_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.target_profile.name
  vpc_security_group_ids = [aws_security_group.target_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "FLAG{SUPPLY_CHAIN_EIC_SUCCESS_$(date +%s)}" > /home/ubuntu/flag.txt
              chown ubuntu:ubuntu /home/ubuntu/flag.txt
              chmod 444 /home/ubuntu/flag.txt
              EOF

  tags = {
    Name = "${var.scenario_name}-target-server-${var.beaver_id}"
  }
}

# SSH 키 생성
resource "tls_private_key" "target_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
