locals {
  codecommit_repo_arn = "arn:aws:codecommit:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-config"
  log_group_arn       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/corp/deploy-pipeline"
  ecr_repo_arn        = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-app"
  s3_artifact_arn     = aws_s3_bucket.artifacts.arn
}

# ── dev-user ────────────────────────────────────────────────────────────────────
# [의도적 취약점] IAM Git 자격증명이 buildspec에 하드코딩되어 CloudWatch 로그에 평문 노출됨

resource "aws_iam_user" "dev_user" {
  name = "dev-user"
  tags = { Scenario = "${var.project_name}-deploy-hijack" }
}

resource "aws_iam_user_policy" "dev_user_codecommit" {
  name = "dev-user-codecommit-policy"
  user = aws_iam_user.dev_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeCommitAccess"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GitPush"
        ]
        # jsn-config 레포에만 한정 — 다른 레포 접근 불가
        Resource = local.codecommit_repo_arn
      }
    ]
  })
}

# CodeCommit HTTPS 자격증명 (service-specific credential)
# 생성된 username/password가 buildspec에 하드코딩되는 것이 취약점의 핵심
resource "aws_iam_service_specific_credential" "dev_user_git" {
  service_name = "codecommit.amazonaws.com"
  user_name    = aws_iam_user.dev_user.name
}

# ── prowler-ec2-role ────────────────────────────────────────────────────────────
# 의도: 로그 그룹 메타데이터(KMS 여부 등)만 확인 가능
# 핵심 제한: logs:GetLogEvents, logs:FilterLogEvents 권한 없음
#            → 로그 내용 직접 조회 불가 → Steampipe로 유도

resource "aws_iam_role" "prowler_ec2" {
  name = "${var.project_name}-prowler-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-prowler-ec2-role" }
}

resource "aws_iam_role_policy" "prowler_ec2_policy" {
  name = "${var.project_name}-prowler-policy"
  role = aws_iam_role.prowler_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsMetadataOnly"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:DescribeMetricFilters"
          # logs:GetLogEvents 없음 — 로그 내용 조회 불가 (의도적)
          # logs:FilterLogEvents 없음 — 로그 검색 불가 (의도적)
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "prowler_ec2" {
  name = "${var.project_name}-prowler-instance-profile"
  role = aws_iam_role.prowler_ec2.name
}

# ── steampipe-ec2-role ──────────────────────────────────────────────────────────
# 의도: 로그 내용 조회 가능 → /corp/deploy-pipeline 에서 Git 자격증명 발견
# Prowler와 달리 GetLogEvents, FilterLogEvents 허용

resource "aws_iam_role" "steampipe_ec2" {
  name = "${var.project_name}-steampipe-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-steampipe-ec2-role" }
}

resource "aws_iam_role_policy" "steampipe_ec2_policy" {
  name = "${var.project_name}-steampipe-policy"
  role = aws_iam_role.steampipe_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",   # Prowler에는 없음 — 역할 분리 핵심
          "logs:FilterLogEvents" # Prowler에는 없음 — 역할 분리 핵심
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "steampipe_ec2" {
  name = "${var.project_name}-steampipe-instance-profile"
  role = aws_iam_role.steampipe_ec2.name
}

# ── codebuild-role ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-codebuild-role" }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${local.log_group_arn}",
          "${local.log_group_arn}:*"
        ]
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPushImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage"
        ]
        Resource = local.ecr_repo_arn
      },
      {
        Sid    = "S3Artifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "${local.s3_artifact_arn}",
          "${local.s3_artifact_arn}/*"
        ]
      },
      {
        Sid    = "CodeCommitPull"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull"
        ]
        Resource = local.codecommit_repo_arn
      }
    ]
  })
}

# ── codedeploy-role ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-codedeploy-role" }
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ── codepipeline-role ────────────────────────────────────────────────────────────

resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-codepipeline-role" }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeCommitSource"
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive"
        ]
        Resource = local.codecommit_repo_arn
      },
      {
        Sid    = "ECSForCodeDeployToECS"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeBuildTrigger"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/${var.project_name}-build"
      },
      {
        Sid    = "CodeDeployTrigger"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Artifacts"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          "${local.s3_artifact_arn}",
          "${local.s3_artifact_arn}/*"
        ]
      },
      {
        Sid    = "EventBridgeForDetectChanges"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:DescribeRule",
          "events:DeleteRule",
          "events:RemoveTargets"
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRoleToServices"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEqualsIfExists = {
            "iam:PassedToService" = [
              "cloudformation.amazonaws.com",
              "elasticbeanstalk.amazonaws.com",
              "ec2.amazonaws.com",
              "ecs-tasks.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# ── ecs-task-execution-role ──────────────────────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-ecs-task-execution-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# FLAG는 Secrets Manager에 보관 → ECS Agent가 컨테이너에 주입
# dev-user에게는 이 권한 없음 → 클론 후 ARN만 보이고 값 읽기 불가
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-ecs-execution-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "GetFlagSecret"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.flag.arn
    }]
  })
}
