resource "aws_vpc" "legacy_bridge_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc-${local.suffix}"
  }
}

resource "aws_internet_gateway" "legacy_bridge_igw" {
  vpc_id = aws_vpc.legacy_bridge_vpc.id

  tags = {
    Name = "${local.name}-igw-${local.suffix}"
  }
}

resource "aws_subnet" "public_gateway_subnet" {
  vpc_id                  = aws_vpc.legacy_bridge_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-subnet-${local.suffix}"
    Tier = "public"
  }
}

resource "aws_subnet" "shadow_api_subnet" {
  vpc_id                  = aws_vpc.legacy_bridge_vpc.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-subnet-${local.suffix}"
    Tier = "private"
  }
}

resource "aws_eip" "nat_gateway_eip" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip-${local.suffix}"
  }

  depends_on = [aws_internet_gateway.legacy_bridge_igw]
}

resource "aws_nat_gateway" "legacy_bridge_natgw" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_gateway_subnet.id

  tags = {
    Name = "${local.name}-natgw-${local.suffix}"
  }

  depends_on = [aws_internet_gateway.legacy_bridge_igw]
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.legacy_bridge_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.legacy_bridge_igw.id
  }

  tags = {
    Name = "${local.name}-public-rt-${local.suffix}"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.legacy_bridge_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.legacy_bridge_natgw.id
  }

  tags = {
    Name = "${local.name}-private-rt-${local.suffix}"
  }
}

resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_gateway_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_assoc" {
  subnet_id      = aws_subnet.shadow_api_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}