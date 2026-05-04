#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario deployment information"
  value = {
    scenario_name  = "policy-rollback"
    scenario_id    = local.scenario_id
    region         = var.region
    whitelisted_ip = local.whitelist_cidr
  }
}

#---------------------------------------
# Leaked Credentials (Starting Point)
#---------------------------------------
output "leaked_credentials" {
  description = "Simulated leaked AWS credentials (starting point)"
  sensitive   = true
  value = {
    aws_access_key_id     = aws_iam_access_key.attacker.id
    aws_secret_access_key = aws_iam_access_key.attacker.secret
  }
}

#---------------------------------------
# Hint
#---------------------------------------
output "hint" {
  description = "Hint for the challenge"
  value       = "The DevOps team forgot to clean up old policy versions after the incident. Check what permissions you had before..."
}

#---------------------------------------
# Start Message
#---------------------------------------
output "start_message" {
  description = "Challenge start message"
  value       = <<-EOF

    ╔══════════════════════════════════════════════════════════════════╗
    ║                      POLICY ROLLBACK                             ║
    ║                      Challenge Ready                             ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  During a production outage, your IAM permissions were           ║
    ║  temporarily elevated. After the incident, they created          ║
    ║  a new restricted policy version.                                ║
    ║                                                                  ║
    ║  But did they clean up the old versions?                         ║
    ║                                                                  ║
    ║  Run: terraform output -json leaked_credentials                  ║
    ║                                                                  ║
    ║  Configure AWS CLI profile and find the flag!                    ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝

  EOF
}

#---------------------------------------
# Verification (Admin Only)
#---------------------------------------
output "verification" {
  description = "For scenario verification only"
  sensitive   = true
  value = {
    secret_name = aws_secretsmanager_secret.flag.name
    secret_arn  = aws_secretsmanager_secret.flag.arn
    policy_arn  = aws_iam_policy.versioned_policy.arn
    user_arn    = aws_iam_user.attacker.arn
  }
}
