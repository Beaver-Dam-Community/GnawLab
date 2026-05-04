#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario information"
  value = {
    scenario_name = "ebs-snapshot-theft"
    scenario_id   = local.scenario_id
    region        = var.region
    whitelist_ip  = local.whitelist_cidr
  }
}

#---------------------------------------
# Credentials Output (Starting Point)
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
                      EBS SNAPSHOT THEFT
                       Scenario Ready
    ============================================================

    You discovered these credentials in a GitHub repository.
    Intelligence suggests a decommissioned server's backup
    might contain sensitive data.

    Run: terraform output -json leaked_credentials

    Configure AWS CLI profile and find the flag!

    Hint: Look for snapshots in the environment...

    ============================================================

  EOF
}

#---------------------------------------
# Infrastructure Info (for attacker use)
#---------------------------------------
output "vpc_id" {
  description = "VPC ID for attacker to use"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Subnet ID for attacker to use"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Security Group ID for attacker to use"
  value       = aws_security_group.ssh.id
}

#---------------------------------------
# Verification (Hidden)
#---------------------------------------
output "verification" {
  description = "For scenario verification only"
  sensitive   = true
  value = {
    snapshot_id   = aws_ebs_snapshot.data.id
    volume_id     = aws_ebs_volume.data.id
    user_arn      = aws_iam_user.attacker.arn
    flag_location = "/backups/db/credentials.bak"
  }
}
