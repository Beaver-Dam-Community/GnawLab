# ── Secrets Manager — FLAG 보관 ────────────────────────────────────────────────
# FLAG 원본을 CodeCommit 밖에 보관 → dev-user는 읽기 권한 없음
# ecsTaskExecutionRole만 GetSecretValue 허용 → ECS Agent가 컨테이너에 주입

resource "aws_secretsmanager_secret" "flag" {
  name                    = "${var.project_name}/flag"
  description             = "CTF flag injected into the ECS task as environment variable"
  recovery_window_in_days = 0 # 즉시 삭제 허용 (CTF 환경 teardown용)

  tags = { Name = "${var.project_name}-flag" }
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id     = aws_secretsmanager_secret.flag.id
  secret_string = "FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}"
}
