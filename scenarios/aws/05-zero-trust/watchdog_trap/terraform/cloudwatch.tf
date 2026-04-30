# [의도적 취약점] KMS 키 없음 — Prowler가 FAIL로 탐지
# 참가자는 Prowler 리포트에서 이 로그 그룹명을 발견하고,
# Steampipe에서 로그 내용을 직접 조회해 Git 자격증명을 획득함

resource "aws_cloudwatch_log_group" "deploy_pipeline" {
  name              = "/corp/deploy-pipeline"
  retention_in_days = 90
  # kms_key_id 미설정 — 의도적 취약점 (KMS 암호화 없음)

  tags = {
    Name     = "deploy-pipeline-logs"
    Scenario = "${var.project_name}-deploy-hijack"
    Vuln     = "no-kms-encryption"
  }
}
