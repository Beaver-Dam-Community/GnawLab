resource "aws_ecs_cluster" "prod_cluster" {
  name = "${local.name}-prod-cluster-${local.suffix}"

  tags = {
    Name = "${local.name}-prod-cluster-${local.suffix}"
  }
}

resource "aws_ecs_task_definition" "webapp_task" {
  family                   = "${local.name}-webapp-${local.suffix}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "beaverpay-webapp"
      image = "${aws_ecr_repository.webapp_ecr.repository_url}:latest"

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name}-webapp-${local.suffix}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name}-webapp-task-${local.suffix}"
  }
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${local.name}-webapp-${local.suffix}"
  retention_in_days = 7

  tags = {
    Name = "${local.name}-ecs-logs-${local.suffix}"
  }
}

resource "aws_ecs_service" "webapp_service" {
  name            = "${local.name}-webapp-service-${local.suffix}"
  cluster         = aws_ecs_cluster.prod_cluster.id
  task_definition = aws_ecs_task_definition.webapp_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  depends_on = [null_resource.push_dummy_image]

  network_configuration {
    subnets          = [aws_subnet.public_subnet.id]
    security_groups  = [aws_security_group.ecs_task_sg.id]
    assign_public_ip = true
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${local.name}-webapp-service-${local.suffix}"
    Role = "prod-webapp"
  }
}
