resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.ecs_log_group_name
  retention_in_days = 1

  tags = {
    Name = "${local.scenario_name}-logs-${local.scenario_id}"
  }
}

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

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# The flag-vault container: an alpine sidecar with the flag baked into its
# filesystem. It does nothing useful at runtime; ECS Exec into it is the
# only intended way to reach the flag.
resource "aws_ecs_task_definition" "flag_vault" {
  family                   = local.ecs_task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.exec.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "flag-vault"
    image     = "public.ecr.aws/docker/library/alpine:3.19"
    essential = true

    # initProcessEnabled is required for ECS Exec sessions to land cleanly
    # inside Fargate task containers.
    linuxParameters = {
      initProcessEnabled = true
    }

    # The flag value comes from SSM Parameter Store via the `secrets` field
    # below, NOT via plain `environment`. This way `ecs:DescribeTaskDefinition`
    # only leaks the parameter ARN, not the value itself.
    secrets = [
      { name = "FLAG", valueFrom = aws_ssm_parameter.flag.arn }
    ]

    entryPoint = ["/bin/sh", "-c"]
    command = [
      "mkdir -p /app/data && printf '%s\\n' \"$FLAG\" > /app/data/flag.txt && chmod 0444 /app/data/flag.txt && unset FLAG && tail -f /dev/null"
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "flag-vault"
      }
    }
  }])

  tags = {
    Name = local.ecs_task_family
  }
}

resource "aws_ecs_service" "main" {
  name                   = local.ecs_service_name
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.flag_vault.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = true

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.fargate.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  tags = {
    Name = local.ecs_service_name
  }

  depends_on = [aws_nat_gateway.main]
}
