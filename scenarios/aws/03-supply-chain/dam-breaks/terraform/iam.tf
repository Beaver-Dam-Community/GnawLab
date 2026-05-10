data "aws_iam_policy_document" "cognito_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.developer_identity_pool.id]
    }
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "collaborator_developer_role" {
  name               = "${local.name}-CollaboratorDeveloperRole-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.cognito_assume_role_policy.json

  tags = {
    Name = "CollaboratorDeveloperRole"
    Role = "collaborator"
  }
}

data "aws_iam_policy_document" "collaborator_policy_doc" {
  statement {
    sid    = "CodeBuildAccess"
    effect = "Allow"
    actions = [
      "codebuild:ListProjects",
      "codebuild:BatchGetProjects",
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRReadAccess"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSReadAccess"
    effect = "Allow"
    actions = [
      "ecs:ListClusters",
      "ecs:ListServices",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMEnumeration"
    effect = "Allow"
    actions = [
      "iam:SimulatePrincipalPolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-CollaboratorDeveloperRole-${local.suffix}"]
  }

  statement {
    sid    = "CloudWatchLogsRead"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/*"]
  }
}

resource "aws_iam_role_policy" "collaborator_policy" {
  name   = "${local.name}-collaborator-policy-${local.suffix}"
  role   = aws_iam_role.collaborator_developer_role.id
  policy = data.aws_iam_policy_document.collaborator_policy_doc.json
}

data "aws_iam_policy_document" "ecs_task_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.name}-ecs-task-role-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = {
    Name = "beaverpay-ecs-task-role"
    Role = "ecs-task"
  }
}

data "aws_iam_policy_document" "ecs_task_policy_doc" {
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.db_credentials.arn,
      aws_secretsmanager_secret.payment_gateway_key.arn,
      aws_secretsmanager_secret.flag.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = "${local.name}-ecs-task-policy-${local.suffix}"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_policy_doc.json
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.name}-ecs-execution-role-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json

  tags = {
    Name = "beaverpay-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "codebuild_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild_service_role" {
  name               = "${local.name}-CodeBuildProdServiceRole-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role_policy.json

  tags = {
    Name = "CodeBuildProdServiceRole"
  }
}

data "aws_iam_policy_document" "codebuild_policy_doc" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRAccess"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ECSUpdateService"
    effect  = "Allow"
    actions = ["ecs:UpdateService"]
    resources = ["arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${local.name}-prod-cluster-${local.suffix}/${local.name}-webapp-service-${local.suffix}"]
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name   = "${local.name}-codebuild-policy-${local.suffix}"
  role   = aws_iam_role.codebuild_service_role.id
  policy = data.aws_iam_policy_document.codebuild_policy_doc.json
}

resource "aws_iam_role" "portal_ec2_role" {
  name = "${local.name}-portal-ec2-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.name}-portal-ec2-role-${local.suffix}"
  }
}

resource "aws_iam_role_policy_attachment" "portal_ec2_ssm" {
  role       = aws_iam_role.portal_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "portal_ec2_profile" {
  name = "${local.name}-portal-ec2-profile-${local.suffix}"
  role = aws_iam_role.portal_ec2_role.name
}
