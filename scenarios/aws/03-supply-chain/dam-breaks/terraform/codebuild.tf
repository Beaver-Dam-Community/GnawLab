resource "aws_codebuild_project" "webapp_prod_build" {
  name          = "${local.name}-webapp-prod-build-${local.suffix}"
  description   = "BeaverPay webapp production build"
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.webapp_ecr.repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "ECS_CLUSTER"
      value = "${local.name}-prod-cluster-${local.suffix}"
    }

    environment_variable {
      name  = "ECS_SERVICE"
      value = "${local.name}-webapp-service-${local.suffix}"
    }

    environment_variable {
      name  = "SECRET_ARN"
      value = aws_secretsmanager_secret.flag.arn
    }
  }

  source {
    type = "NO_SOURCE"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        pre_build:
          commands:
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI
        build:
          commands:
            - echo Build started on `date`
            - docker build -t $REPOSITORY_URI:latest .
        post_build:
          commands:
            - docker push $REPOSITORY_URI:latest
            - aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment
            - echo Build completed on `date`
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name}-webapp-prod-${local.suffix}"
      stream_name = "build-log"
    }
  }

  tags = {
    Name = "${local.name}-webapp-prod-build-${local.suffix}"
    Role = "prod-pipeline"
  }
}

resource "aws_codebuild_project" "webapp_qa_build" {
  name          = "${local.name}-webapp-qa-build-${local.suffix}"
  description   = "BeaverPay webapp QA build"
  service_role  = aws_iam_role.codebuild_service_role.arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.webapp_ecr.repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }
  }

  source {
    type = "NO_SOURCE"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        build:
          commands:
            - echo QA build started on `date`
            - echo QA build completed
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name}-webapp-qa-${local.suffix}"
      stream_name = "build-log"
    }
  }

  tags = {
    Name = "${local.name}-webapp-qa-build-${local.suffix}"
    Role = "qa-pipeline"
  }
}
