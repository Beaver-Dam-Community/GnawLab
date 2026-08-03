resource "aws_security_group" "vulnboard" {
  name        = local.vulnboard_sg_name
  description = "VulnBoard public ingress (whitelisted) and full egress for Docker pulls."
  vpc_id      = aws_vpc.main.id

  # The scenario story is that this rule was opened to 0.0.0.0/0 during a
  # recruiting push and never rolled back. In the deployed lab, however,
  # we whitelist only the learner's IP for safety.
  ingress {
    description = "VulnBoard web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.vulnboard_sg_name
  }
}

resource "aws_security_group" "fargate" {
  name        = local.fargate_sg_name
  description = "Fargate task SG. No public ingress; egress to NAT for ECR/SSM."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow VulnBoard EC2 to reach the task (not used directly, kept for symmetry)"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.vulnboard.id]
  }

  egress {
    description = "Allow all outbound (NAT for ECR pulls and SSM channels)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.fargate_sg_name
  }
}
