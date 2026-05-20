#---------------------------------------
# Secrets Manager — flag storage
#
# The flag is stored here intentionally so that:
#   - The attacker (ReadOnly user) cannot read it directly.
#   - The ASG-launched EC2 instance profile can. Both the legitimate
#     ticketing AMI and the attacker's malicious AMI inherit this
#     instance profile, which is the asymmetry the WhoAMI attack
#     exploits: the legitimate app could fetch app secrets at boot,
#     and a malicious AMI piggybacks on the same privilege to
#     exfiltrate the flag.
#
# `recovery_window_in_days = 0` makes destroy immediate (no 7–30 day
# wait), which matches the lab's expected lifecycle.
#---------------------------------------
resource "aws_secretsmanager_secret" "flag" {
  name                    = local.secret_name
  description             = "BeaverDam ticketing app flag (intentionally exposed to the EC2 instance profile)"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = local.secret_name
  })
}

resource "aws_secretsmanager_secret_version" "flag" {
  secret_id = aws_secretsmanager_secret.flag.id

  # Realistic ticketing-platform secrets bundle. The flag lives alongside
  # production-looking credentials so the participant can see exactly what
  # an attacker would walk away with when an unverified golden AMI is
  # promoted into production.
  secret_string = jsonencode({
    db_host         = "ticketing-db.internal.beaverdam.com"
    db_port         = 5432
    db_name         = "ticketing_prod"
    db_user         = "ticketing_app"
    db_password     = "Tr0ub4dor&3-internal"
    payment_api_key = "sk_live_beaverdam_payments_xxxxxxxxxxxxxxxx"
    smtp_password   = "BeaverDamSmtp!2026"
    flag            = var.flag_value
  })
}
