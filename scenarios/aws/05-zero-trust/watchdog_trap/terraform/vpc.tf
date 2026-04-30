# ── VPC ────────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ── Internet Gateway ────────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

# ── NAT Gateway ─────────────────────────────────────────────────────────────────
# NAT placed in public_a → guarantees outbound for tools_subnet (prowler/steampipe)
# ECS private subnets are also connected here

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id # NAT must be in a public subnet (with an IGW route)

  tags = { Name = "${var.project_name}-nat-gw" }

  depends_on = [aws_internet_gateway.main]
}

# ── Subnets ─────────────────────────────────────────────────────────────────────

# security_subnet — dedicated to webapp (IGW route retained, exposed externally via EIP)
# map_public_ip_on_launch = true: ensures internet access via a temporary public IP during user_data execution (before EIP attachment)
# The temporary IP is automatically released after EIP attachment — no security impact since this is a webapp-only subnet
resource "aws_subnet" "security" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-security-subnet" }
}

# tools_subnet — hosts prowler + steampipe (NAT route)
# Outbound via NAT GW without a public IP → allows package installation
# Inbound restricted to webapp-sg only via SG (dashboard-sg)
resource "aws_subnet" "tools" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-tools-subnet" }
}

# public_subnet_a / _b — hosts ALB (multi-AZ required) + NAT GW placement
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public-b" }
}

# private_subnet_a / _b — hosts ECS Fargate (NAT route)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "${var.project_name}-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "${var.aws_region}b"

  tags = { Name = "${var.project_name}-private-b" }
}

# ── Route Tables ────────────────────────────────────────────────────────────────

# public (IGW): security_subnet + ALB public subnets
# webapp EIP inbound depends on this route — do NOT change to NAT
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "security" {
  subnet_id      = aws_subnet.security.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# nat: tools_subnet + ECS private subnets → routed through NAT GW
resource "aws_route_table" "nat" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "${var.project_name}-rt-nat" }
}

resource "aws_route_table_association" "tools" {
  subnet_id      = aws_subnet.tools.id
  route_table_id = aws_route_table.nat.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.nat.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.nat.id
}

# ── Security Groups ─────────────────────────────────────────────────────────────

# webapp-sg — JSN Incident Report Generator (sole external entry point)
resource "aws_security_group" "webapp" {
  name        = "${var.project_name}-webapp-sg"
  description = "External access for JSN Incident Report Generator SSTI RCE entrypoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-webapp-sg" }
}

# dashboard-sg — Prowler + Steampipe (inbound from webapp-sg only)
# Placed in tools_subnet with no public IP + double-blocked by SG
resource "aws_security_group" "dashboard" {
  name        = "${var.project_name}-dashboard-sg"
  description = "Internal Prowler and Steampipe access from webapp-sg only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Prowler from webapp-sg"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.webapp.id]
  }

  ingress {
    description     = "Steampipe from webapp-sg"
    from_port       = 9194
    to_port         = 9194
    protocol        = "tcp"
    security_groups = [aws_security_group.webapp.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-dashboard-sg" }
}

# alb-sg — ALB (port 80 prod + 8080 CodeDeploy test)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: port 80 (prod) + 8080 (CodeDeploy test)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP production"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP test (CodeDeploy Blue/Green validation)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ecs-sg — ECS Fargate (port 3000 inbound from ALB only)
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "ECS Fargate: port 3000 from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ecs-sg" }
}
