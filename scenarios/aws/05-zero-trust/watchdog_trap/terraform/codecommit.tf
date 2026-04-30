resource "aws_codecommit_repository" "config" {
  repository_name = local.codecommit_repo_name
  description     = "Repository for BeaverDam ECS deployment configuration files"

  tags = { Name = local.codecommit_repo_name }
}

# ── Initial file seeding is performed outside of Terraform ─────────────────────────────────────
# The aws_codecommit_file resource causes validation errors and has been removed
# Seeding logic: refer to the seed_codecommit() function in start.sh
#
# Files to seed:
#   Dockerfile            — public.ecr.aws/docker/library/node:18-alpine, FLAG env -> /run/secrets/flag, port 3000
#   appspec.yml           — CodeDeploy ECS Blue/Green configuration
#   task-definition.json  — <IMAGE1_NAME> placeholder, includes secrets ARN, command field is the tampering target
# The original FLAG is stored in Secrets Manager (not in CodeCommit)
