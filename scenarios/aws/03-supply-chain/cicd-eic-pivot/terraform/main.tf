resource "aws_vpc" "scenario_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = local.vpc_name })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.scenario_vpc.id

  tags = merge(local.common_tags, { Name = local.igw_name })
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.scenario_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = merge(local.common_tags, { Name = local.public_subnet_name })
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.scenario_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.region}a"

  tags = merge(local.common_tags, { Name = local.private_subnet_name })
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.scenario_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.common_tags, { Name = local.public_rt_name })
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.scenario_vpc.id

  tags = merge(local.common_tags, { Name = local.private_rt_name })
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}
