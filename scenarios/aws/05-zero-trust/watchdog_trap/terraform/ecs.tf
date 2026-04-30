# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = { Name = "${var.project_name}-cluster" }
}

# ── Bootstrap Task Definition ─────────────────────────────────────────────────
# Used for initial service creation (desired_count=0 so it does not actually run)
# Actual deployments use the task definition registered by CodeDeploy via task-definition.json + imageDetail.json

resource "aws_ecs_task_definition" "bootstrap" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "${var.project_name}-app"
    image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
    essential = true
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/corp/deploy-pipeline"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${var.project_name}-app-bootstrap" }
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bootstrap.arn
  desired_count   = 1 # Uses bootstrap image until the first pipeline run (pull failure tolerated); CodeDeploy replaces it
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "${var.project_name}-app"
    container_port   = 3000
  }

  deployment_controller {
    type = "CODE_DEPLOY" # Required for CodeDeploy Blue/Green deployments
  }

  lifecycle {
    # CodeDeploy directly manages task_definition and load_balancer
    # desired_count is set by CodeDeploy after each deployment, so it is ignored here
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  tags = { Name = "${var.project_name}-service" }
}
