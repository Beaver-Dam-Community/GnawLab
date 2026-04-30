# ── CodeBuild Project ─────────────────────────────────────────────────────────
# [Intentional Vulnerability] dev-user Git credentials are hardcoded inline in the buildspec
# → The git clone command is recorded in /corp/deploy-pipeline logs during CodeBuild execution
# → Querying the logs via Steampipe exposes the credentials in plaintext

resource "aws_codebuild_project" "main" {
  name         = "${var.project_name}-build"
  description  = "Build the JSN application Docker image and push it to ECR"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true # Required for Docker builds

    environment_variable {
      name  = "ECR_REPO_URI"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
  }

  source {
    type = "CODEPIPELINE"

    # Inline buildspec: dev-user Git credential values are inserted in plaintext at Terraform render time
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo "Authenticating to Amazon ECR..."
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
            - echo "Fetching latest config from CodeCommit..."
            - REPO_USER=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe=""))' '${aws_iam_service_specific_credential.dev_user_git.service_user_name}')
            - REPO_PASS=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe=""))' '${aws_iam_service_specific_credential.dev_user_git.service_password}')
            - REPO_HOST="${replace(aws_codecommit_repository.config.clone_url_http, "https://", "")}"
            - echo "Cloning https://$REPO_USER:$REPO_PASS@$REPO_HOST"
            - git clone "https://$REPO_USER:$REPO_PASS@$REPO_HOST" /tmp/jsn-config
            - cp /tmp/jsn-config/Dockerfile .
        build:
          commands:
            - IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
            - echo "Building image $ECR_REPO_URI:$IMAGE_TAG ..."
            - docker build -t $ECR_REPO_URI:$IMAGE_TAG .
        post_build:
          commands:
            - docker push $ECR_REPO_URI:$IMAGE_TAG
            - printf '{"ImageURI":"%s:%s"}' "$ECR_REPO_URI" "$IMAGE_TAG" > imageDetail.json
            - echo "Build complete. Image pushed."
      artifacts:
        files:
          - imageDetail.json
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/corp/deploy-pipeline"
      stream_name = "codebuild"
    }
  }

  tags = { Name = "${var.project_name}-build" }
}
