#---------------------------------------
# Application Load Balancer
#---------------------------------------
resource "aws_lb" "main" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Idle timeout kept low so the load-test traffic cycles connections quickly,
  # which makes CPU pressure show up faster on the ASG.
  idle_timeout = 30

  tags = merge(local.common_tags, {
    Name = local.alb_name
  })
}

#---------------------------------------
# Target Group
#---------------------------------------
resource "aws_lb_target_group" "app" {
  name     = "${local.scenario_name}-tg-${local.scenario_id}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Short deregistration delay so cycling instances during scale-out
  # doesn't keep stale connections open for too long.
  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-tg-${local.scenario_id}"
  })
}

#---------------------------------------
# Listener
#---------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
