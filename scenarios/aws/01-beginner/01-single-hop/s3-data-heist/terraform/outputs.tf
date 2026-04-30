#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario information"
  value = {
    scenario_name = "s3-data-heist"
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
                        S3 DATA HEIST
                       Scenario Ready
    ============================================================

    You discovered these credentials in a GitHub repository.

    Run: terraform output -json leaked_credentials

    Configure AWS CLI profile and find the flag!

    ============================================================

  EOF
}

#---------------------------------------
# Verification (Hidden)
#---------------------------------------
output "verification" {
  description = "For scenario verification only"
  sensitive   = true
  value = {
    bucket_name = aws_s3_bucket.data.id
    flag_key    = aws_s3_object.flag.key
    user_arn    = aws_iam_user.attacker.arn
  }
}
