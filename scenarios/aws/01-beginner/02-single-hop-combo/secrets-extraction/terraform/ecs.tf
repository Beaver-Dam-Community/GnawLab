# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = local.ecs_cluster_name
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.scenario_name}-${local.scenario_id}"
  retention_in_days = 1

  tags = {
    Name = "/ecs/${local.scenario_name}-${local.scenario_id}"
  }
}

# ECS Task Definition with vulnerable Flask app
resource "aws_ecs_task_definition" "webapp" {
  family                   = "${local.scenario_name}-webapp-${local.scenario_id}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "webapp"
      image     = "python:3.11-slim"
      essential = true
      cpu       = 256
      memory    = 512

      portMappings = [{
        containerPort = 5000
        hostPort      = 5000
        protocol      = "tcp"
      }]

      entryPoint = ["sh", "-c"]
      command = [
        "apt-get update && apt-get install -y imagemagick curl && pip install flask && cat > /app.py << 'PYEOF'\n${local.flask_app_code}\nPYEOF\npython /app.py"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "webapp"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = {
    Name = "${local.scenario_name}-task-${local.scenario_id}"
  }
}

# ECS Service
resource "aws_ecs_service" "webapp" {
  name            = local.ecs_service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.webapp.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "webapp"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = local.ecs_service_name
  }
}
