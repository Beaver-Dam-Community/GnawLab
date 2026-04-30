# ── dev-user ────────────────────────────────────────────────────────────────────
# [Intentional Vulnerability] IAM Git credentials are hardcoded in the buildspec and exposed in plaintext in CloudWatch logs

resource "aws_iam_user" "dev_user" {
  name = "${local.scenario_name}-dev-user-${local.scenario_id}"
  tags = { Scenario = "${local.scenario_name}-deploy-hijack" }
}

resource "aws_iam_user_policy" "dev_user_codecommit" {
  name = "${local.scenario_name}-dev-user-policy-${local.scenario_id}"
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
        # Scoped to config repo only — no access to other repositories
        Resource = local.codecommit_repo_arn
      }
    ]
  })
}

# CodeCommit HTTPS credentials (service-specific credential)
# The core of the vulnerability is that the generated username/password are hardcoded in the buildspec
resource "aws_iam_service_specific_credential" "dev_user_git" {
  service_name = "codecommit.amazonaws.com"
  user_name    = aws_iam_user.dev_user.name
}

# ── prowler-ec2-role ────────────────────────────────────────────────────────────
# Intent: can only inspect log group metadata (e.g., KMS encryption status)
# Key restriction: no logs:GetLogEvents or logs:FilterLogEvents permission
#                  → cannot directly read log contents → directs participants to Steampipe

resource "aws_iam_role" "prowler_ec2" {
  name = "${local.scenario_name}-prowler-ec2-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-prowler-ec2-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy" "prowler_ec2_policy" {
  name = "${local.scenario_name}-prowler-policy-${local.scenario_id}"
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
          # logs:GetLogEvents absent — cannot read log content (intentional)
          # logs:FilterLogEvents absent — cannot search logs (intentional)
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
  name = "${local.scenario_name}-prowler-instance-profile-${local.scenario_id}"
  role = aws_iam_role.prowler_ec2.name
}

# ── steampipe-ec2-role ──────────────────────────────────────────────────────────
# Intent: can read log content → discovers Git credentials from the deploy-pipeline log group
# Unlike Prowler, GetLogEvents and FilterLogEvents are permitted

resource "aws_iam_role" "steampipe_ec2" {
  name = "${local.scenario_name}-steampipe-ec2-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-steampipe-ec2-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy" "steampipe_ec2_policy" {
  name = "${local.scenario_name}-steampipe-policy-${local.scenario_id}"
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
          "logs:GetLogEvents",   # Absent in Prowler role — key to role separation
          "logs:FilterLogEvents" # Absent in Prowler role — key to role separation
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "steampipe_ec2" {
  name = "${local.scenario_name}-steampipe-instance-profile-${local.scenario_id}"
  role = aws_iam_role.steampipe_ec2.name
}

# ── codebuild-role ──────────────────────────────────────────────────────────────

resource "aws_iam_role" "codebuild" {
  name = "${local.scenario_name}-codebuild-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-codebuild-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${local.scenario_name}-codebuild-policy-${local.scenario_id}"
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
  name = "${local.scenario_name}-codedeploy-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-codedeploy-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ── codepipeline-role ────────────────────────────────────────────────────────────

resource "aws_iam_role" "codepipeline" {
  name = "${local.scenario_name}-codepipeline-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-codepipeline-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.scenario_name}-codepipeline-policy-${local.scenario_id}"
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
        Resource = "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/${local.scenario_name}-build-${local.scenario_id}"
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
  name = "${local.scenario_name}-ecs-task-execution-role-${local.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.scenario_name}-ecs-task-execution-role-${local.scenario_id}" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# FLAG is stored in Secrets Manager → ECS Agent injects it into the container
# dev-user does not have this permission → after cloning, only the ARN is visible; the value cannot be read
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.scenario_name}-ecs-execution-secrets-policy-${local.scenario_id}"
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
