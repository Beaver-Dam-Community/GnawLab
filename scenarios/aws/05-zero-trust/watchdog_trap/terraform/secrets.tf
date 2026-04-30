# ── Secrets Manager — FLAG storage ────────────────────────────────────────────────
# The original FLAG is stored outside CodeCommit → dev-user has no read permission
# Only ecsTaskExecutionRole is allowed GetSecretValue → ECS Agent injects it into the container

resource "aws_secretsmanager_secret" "flag" {
  name                    = "${local.scenario_name}/flag-${local.scenario_id}"
  description             = "CTF flag injected into the ECS task as environment variable"
  recovery_window_in_days = 0 # allow immediate deletion (for CTF environment teardown)

  tags = { Name = "${local.scenario_name}-flag-${local.scenario_id}" }
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id     = aws_secretsmanager_secret.flag.id
  secret_string = "FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}"
}
