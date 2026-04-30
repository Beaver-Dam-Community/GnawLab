resource "aws_codecommit_repository" "config" {
  repository_name = "${var.project_name}-config"
  description     = "Repository for JSN ECS deployment configuration files"

  tags = { Name = "${var.project_name}-config" }
}

# ── 초기 파일 시딩은 Terraform 외부에서 수행 ─────────────────────────────────────
# aws_codecommit_file 리소스는 validate 오류를 유발하므로 제거
# 시딩 로직: start.sh의 seed_codecommit() 함수 참고
#
# 시딩 파일 목록:
#   Dockerfile            — public.ecr.aws/docker/library/node:18-alpine, FLAG env -> /run/secrets/flag, port 3000
#   appspec.yml           — CodeDeploy ECS Blue/Green 설정
#   task-definition.json  — <IMAGE1_NAME> placeholder, secrets ARN 포함, command 필드 변조 대상
# FLAG 원본은 Secrets Manager에 보관 (CodeCommit에 없음)
