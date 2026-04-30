# ── CodePipeline ─────────────────────────────────────────────────────────────
# Source (CodeCommit main) → Build (CodeBuild) → Deploy (CodeDeploy ECS B/G)
# CodeCommit push -> automatic pipeline trigger (core attack chain)

resource "aws_codepipeline" "main" {
  name     = "${local.scenario_name}-pipeline-${local.scenario_id}"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # ── Stage 1: Source ──────────────────────────────────────────────────────────
  stage {
    name = "Source"

    action {
      name             = "CodeCommit"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = local.codecommit_repo_name
        BranchName           = "main"
        PollForSourceChanges = "true" # git push triggers the pipeline automatically
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  # ── Stage 2: Build ───────────────────────────────────────────────────────────
  stage {
    name = "Build"

    action {
      name             = "CodeBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  # ── Stage 3: Deploy ──────────────────────────────────────────────────────────
  stage {
    name = "Deploy"

    action {
      name            = "CodeDeployToECS"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["SourceArtifact", "BuildArtifact"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.main.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.main.deployment_group_name
        TaskDefinitionTemplateArtifact = "SourceArtifact"
        TaskDefinitionTemplatePath     = "task-definition.json"
        AppSpecTemplateArtifact        = "SourceArtifact"
        AppSpecTemplatePath            = "appspec.yml"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME" # substitutes <IMAGE1_NAME> placeholder in task-definition.json
      }
    }
  }
}
