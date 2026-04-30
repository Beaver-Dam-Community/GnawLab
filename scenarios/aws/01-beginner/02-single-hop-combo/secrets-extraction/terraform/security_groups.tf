# ALB Security Group - Only whitelisted IP can access
resource "aws_security_group" "alb" {
  name        = "${local.scenario_name}-alb-sg-${local.scenario_id}"
  description = "ALB Security Group - IP whitelisted"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
    description = "HTTP from whitelisted IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${local.scenario_name}-alb-sg-${local.scenario_id}"
  }
}

# ECS Security Group - Only ALB can access
resource "aws_security_group" "ecs" {
  name        = "${local.scenario_name}-ecs-sg-${local.scenario_id}"
  description = "ECS Security Group - ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (for pulling images, etc.)"
  }

  tags = {
    Name = "${local.scenario_name}-ecs-sg-${local.scenario_id}"
  }
}
