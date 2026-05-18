# --- EC2 (VulnBoard) instance role ---------------------------------------
#
# This role represents the scenario's IAM accretion problem: ECS read/exec
# permissions were granted during the 2023 platform-automation push for a
# self-service deploy tool that has since been retired, but the role itself
# was never trimmed. The presence of ecs:ExecuteCommand here is the
# realistic-misconfiguration anchor for the Phase 4 pivot.

resource "aws_iam_role" "app" {
  name = local.app_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = local.app_role_name }
}

resource "aws_iam_role_policy" "app_inline" {
  name = "${local.scenario_name}-app-policy-${local.scenario_id}"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Enumeration"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSEnumeration"
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:DescribeClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTaskDefinition",
          "ecs:ListContainerInstances",
        ]
        Resource = "*"
      },
      {
        # Scoped to this scenario's cluster so leftover credentials cannot be
        # used to exec into unrelated tasks if the lab is deployed in a
        # shared account.
        Sid    = "ECSExecCommand"
        Effect = "Allow"
        Action = [
          "ecs:ExecuteCommand",
        ]
        Resource = [
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.ecs_cluster_name}",
          "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task/${local.ecs_cluster_name}/*",
        ]
      },
      {
        Sid    = "SSMMessagesForExec"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = local.app_profile_name
  role = aws_iam_role.app.name
}

# --- ECS Task Execution Role (pull image + ship logs) --------------------

resource "aws_iam_role" "exec" {
  name = local.exec_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = local.exec_role_name }
}

resource "aws_iam_role_policy_attachment" "exec_managed" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Role (runtime identity inside the flag container) ----------
#
# Minimal: only the SSM Messages permissions required for ECS Exec to land
# an interactive shell in the container. No data-plane permissions; the
# only thing of value here is the flag file on the container's filesystem.

resource "aws_iam_role" "task" {
  name = local.task_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = local.task_role_name }
}

resource "aws_iam_role_policy" "task_inline" {
  name = "${local.scenario_name}-task-policy-${local.scenario_id}"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SSMMessagesForExec"
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}
