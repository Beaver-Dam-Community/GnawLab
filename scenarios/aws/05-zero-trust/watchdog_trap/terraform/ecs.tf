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
# 초기 서비스 생성용 (desired_count=0이므로 실제 구동 안 됨)
# 실제 배포는 CodeDeploy가 task-definition.json + imageDetail.json으로 등록한 task def 사용

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
  desired_count   = 1 # 파이프라인 첫 실행 전까지 bootstrap image로 (pull 실패 허용); CodeDeploy가 교체
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
    type = "CODE_DEPLOY" # CodeDeploy Blue/Green 필수
  }

  lifecycle {
    # CodeDeploy가 task_definition, load_balancer를 직접 관리
    # desired_count는 CodeDeploy 배포 이후 CodeDeploy가 설정하므로 ignore
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  tags = { Name = "${var.project_name}-service" }
}
