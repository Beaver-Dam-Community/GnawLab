# ── Information provided to participants ──────────────────────────────────────────────────────────────
output "webapp_url" {
  description = "BeaverDam Incident Report Generator URL for participants"
  value       = "http://${aws_eip.webapp.public_ip}"
}

# ── Internal reference for start.sh / teardown ──────────────────────────────────────────────
output "webapp_public_ip" { value = aws_eip.webapp.public_ip }
output "pipeline_name" { value = aws_codepipeline.main.name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "s3_artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "ecs_service_name" { value = aws_ecs_service.main.name }
output "codecommit_clone_url_http" { value = aws_codecommit_repository.config.clone_url_http }

output "dev_user_codecommit_username" {
  value = aws_iam_service_specific_credential.dev_user_git.service_user_name
}
output "dev_user_codecommit_password" {
  value     = aws_iam_service_specific_credential.dev_user_git.service_password
  sensitive = true
}
output "ecs_task_execution_role_arn" { value = aws_iam_role.ecs_task_execution.arn }
output "flag_secret_arn" { value = aws_secretsmanager_secret.flag.arn }

# ── Operator reference only (not exposed to participants) ──────────────────────────────────
output "prowler_private_ip" {
  value     = aws_instance.prowler.private_ip
  sensitive = true
}
output "steampipe_private_ip" {
  value     = aws_instance.steampipe.private_ip
  sensitive = true
}
output "alb_dns_name" { value = aws_lb.main.dns_name }
output "codebuild_project" { value = aws_codebuild_project.main.name }
output "codedeploy_app" { value = aws_codedeploy_app.main.name }
