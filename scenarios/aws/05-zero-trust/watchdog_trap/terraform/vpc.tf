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
# public_a에 NAT 배치 → tools_subnet (prowler/steampipe) outbound 보장
# ECS private subnet도 여기에 연결

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id # NAT는 반드시 public subnet(IGW 라우트)에 있어야 함

  tags = { Name = "${var.project_name}-nat-gw" }

  depends_on = [aws_internet_gateway.main]
}

# ── Subnets ─────────────────────────────────────────────────────────────────────

# security_subnet — webapp 전용 (IGW 라우트 유지, EIP로 외부 노출)
# map_public_ip_on_launch = true: user_data 실행 시(EIP 부착 전) 임시 public IP로 인터넷 접근 보장
# EIP 부착 후 임시 IP는 자동 회수됨 — webapp 전용 서브넷이므로 보안 영향 없음
resource "aws_subnet" "security" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-security-subnet" }
}

# tools_subnet — prowler + steampipe 배치 (NAT 라우트)
# public IP 없이 NAT GW로 outbound → 패키지 설치 가능
# SG(dashboard-sg)로 인바운드는 webapp-sg에서만
resource "aws_subnet" "tools" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-tools-subnet" }
}

# public_subnet_a / _b — ALB 배치 (AZ 분산 필수) + NAT GW 배치
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

# private_subnet_a / _b — ECS Fargate 배치 (NAT 라우트)
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
# webapp EIP 인바운드가 이 라우트에 의존함 — 절대 NAT로 변경 금지
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

# nat: tools_subnet + ECS private subnets → NAT GW
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

# webapp-sg — JSN Incident Report Generator (유일한 외부 진입점)
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

# dashboard-sg — Prowler + Steampipe (webapp-sg에서만 인바운드)
# tools_subnet에 배치되어 public IP 없음 + SG로 이중 차단
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

# alb-sg — ALB (80 prod + 8080 CodeDeploy test)
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

# ecs-sg — ECS Fargate (ALB에서만 3000 인바운드)
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
