#---------------------------------------
# VPC
#---------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = local.vpc_name
  })
}

#---------------------------------------
# Internet Gateway
#---------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-igw-${local.scenario_id}"
  })
}

#---------------------------------------
# Public Subnets (2 AZs for ALB)
#---------------------------------------
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-public-${count.index + 1}-${local.scenario_id}"
    Tier = "public"
  })
}

#---------------------------------------
# Route Table — public
#---------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-public-rt-${local.scenario_id}"
  })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#---------------------------------------
# Security Group — ALB
# Only the participant's IP is allowed on 80
#---------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.scenario_name}-alb-sg-${local.scenario_id}"
  description = "ALB ingress restricted to the participant whitelisted IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from whitelisted IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-alb-sg-${local.scenario_id}"
  })
}

#---------------------------------------
# Security Group — EC2 instances behind the ALB
# Only the ALB SG can reach the instance application port
#---------------------------------------
resource "aws_security_group" "instance" {
  name        = "${local.scenario_name}-instance-sg-${local.scenario_id}"
  description = "Application instances reachable only from the ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-instance-sg-${local.scenario_id}"
  })
}
