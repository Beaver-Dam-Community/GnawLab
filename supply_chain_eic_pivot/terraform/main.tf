# VPC 정의
resource "aws_vpc" "scenario_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.scenario_vpc.id

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-igw"
  }
}

# Public Subnet (GitLab, Bastion 위치)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.scenario_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-public-subnet"
  }
}

# Private Subnet (Target Server 위치)
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.scenario_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-private-subnet"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.scenario_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-public-rt"
  }
}

# Route Table Association (Public)
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Subnet용 Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.scenario_vpc.id

  tags = {
    Name = "${var.scenario_name}-${var.beaver_id}-private-rt"
  }
}

# Route Table Association (Private)
resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}
