# ── Application Load Balancer ─────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.scenario_name}-alb-${local.scenario_id}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "${local.scenario_name}-alb-${local.scenario_id}" }
}

# ── Target Groups (Blue / Green) ──────────────────────────────────────────────

resource "aws_lb_target_group" "blue" {
  name        = "${local.scenario_name}-blue-${local.scenario_id}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate requires ip target type

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "${local.scenario_name}-blue-tg-${local.scenario_id}" }
}

resource "aws_lb_target_group" "green" {
  name        = "${local.scenario_name}-green-${local.scenario_id}"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "${local.scenario_name}-green-tg-${local.scenario_id}" }
}

# ── Listeners ─────────────────────────────────────────────────────────────────

# Production listener — CodeDeploy switches traffic here during Blue/Green
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    ignore_changes = [default_action] # CodeDeploy owns this after first deploy
  }
}

# Test listener — CodeDeploy routes test traffic during validation phase
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}
