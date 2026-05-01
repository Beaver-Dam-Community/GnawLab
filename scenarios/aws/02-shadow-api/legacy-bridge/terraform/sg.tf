resource "aws_security_group" "public_gateway_sg" {
  name        = "${local.name}-public-gateway-sg-${local.suffix}"
  description = "Public ingress for the v5 portal"
  vpc_id      = aws_vpc.legacy_bridge_vpc.id

  ingress {
    description = "v5 portal HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-public-gateway-sg-${local.suffix}"
  }
}

resource "aws_security_group" "shadow_api_sg" {
  name        = "${local.name}-shadow-api-sg-${local.suffix}"
  description = "Internal-only v1 API. Reachable from the v5 gateway only."
  vpc_id      = aws_vpc.legacy_bridge_vpc.id

  ingress {
    description     = "v1 API from public_gateway_sg only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public_gateway_sg.id]
  }

  egress {
    description = "All egress for SSRF target reachability and package install"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-shadow-api-sg-${local.suffix}"
  }
}