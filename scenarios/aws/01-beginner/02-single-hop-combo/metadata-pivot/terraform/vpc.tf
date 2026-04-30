#---------------------------------------
# VPC
#---------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

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
# Public Subnet
#---------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-public-${local.scenario_id}"
  })
}

#---------------------------------------
# Route Table
#---------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-rt-${local.scenario_id}"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#---------------------------------------
# Security Group
#---------------------------------------
resource "aws_security_group" "web" {
  name        = local.sg_name
  description = "Security group for vulnerable web application"
  vpc_id      = aws_vpc.main.id

  # HTTP from whitelisted IP only
  ingress {
    description = "HTTP from whitelisted IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.whitelist_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.sg_name
  })
}
