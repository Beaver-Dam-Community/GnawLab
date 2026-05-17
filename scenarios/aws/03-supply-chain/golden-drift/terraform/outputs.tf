#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario deployment information"
  value = {
    scenario_name = "golden-drift"
    scenario_id   = local.scenario_id
    region        = var.region
    whitelist_ip  = local.whitelist_cidr
  }
}

#---------------------------------------
# Starting Point — Leaked Credentials
#---------------------------------------
output "leaked_credentials" {
  description = "Simulated leaked AWS credentials (starting point)"
  sensitive   = true
  value = {
    aws_access_key_id     = aws_iam_access_key.attacker.id
    aws_secret_access_key = aws_iam_access_key.attacker.secret
  }
}

output "start_message" {
  description = "Starting point message"
  value       = <<-EOF

    ============================================================
                         GOLDEN DRIFT
                        Scenario Ready
    ============================================================

    You have obtained AWS credentials with read-only access.

    Run: terraform output -json leaked_credentials

    Configure the AWS CLI profile and find the flag.

    ============================================================

  EOF
}

#---------------------------------------
# Verification (Hidden — admin use only)
#---------------------------------------
output "verification" {
  description = "For scenario verification only"
  sensitive   = true
  value = {
    alb_dns_name       = aws_lb.main.dns_name
    golden_ami_id      = aws_ami_from_instance.golden.id
    golden_ami_name    = aws_ami_from_instance.golden.name
    ami_name_prefix    = local.ami_name_prefix
    ssm_parameter_name = local.ssm_parameter_name
    secret_arn         = aws_secretsmanager_secret.flag.arn
    attacker_user_arn  = aws_iam_user.attacker.arn
    lambda_name        = aws_lambda_function.golden_updater.function_name
  }
}

#---------------------------------------
# Public Endpoint (non-sensitive)
#---------------------------------------
output "ticketing_url" {
  description = "URL of the BeaverDam ticketing web application"
  value       = "http://${aws_lb.main.dns_name}"
}
