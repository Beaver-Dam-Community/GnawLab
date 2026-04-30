# Web application URL
output "webapp_url" {
  description = "URL to access the vulnerable web application"
  value       = "http://${aws_lb.main.dns_name}"
}

# Scenario information
output "scenario_info" {
  description = "Scenario deployment information"
  value = {
    scenario_name  = "secrets-extraction"
    scenario_id    = local.scenario_id
    region         = var.region
    whitelisted_ip = local.whitelist_cidr
  }
}

# Hint for the challenge
output "hint" {
  description = "Hint for the challenge"
  value       = "The image resizing service uses ImageMagick. What happens if you provide unexpected input to the dimensions field?"
}

# Start message
output "start_message" {
  description = "Challenge start message"
  value       = <<-EOF

    ╔══════════════════════════════════════════════════════════════════╗
    ║                    SECRETS EXTRACTION                            ║
    ║                      Challenge Ready                             ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  Target: ${aws_lb.main.dns_name}
    ║                                                                  ║
    ║  Scenario: Beaver Finance Corp runs an image processing         ║
    ║  service on ECS. Find the vulnerability and extract the flag    ║
    ║  from their secrets vault.                                      ║
    ║                                                                  ║
    ║  Hint: The service uses ImageMagick for image processing...     ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝

  EOF
}

# Admin-only outputs (sensitive)
output "flag_secret_name" {
  description = "Name of the secret containing the flag (admin only)"
  value       = aws_secretsmanager_secret.flag.name
  sensitive   = true
}

output "task_role_arn" {
  description = "ARN of the ECS task role (admin only)"
  value       = aws_iam_role.ecs_task.arn
  sensitive   = true
}
