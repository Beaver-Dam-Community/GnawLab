#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario information"
  value = {
    scenario_name = "obfuscated-policy"
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
                       OBFUSCATED POLICY
                       Scenario Ready
    ============================================================

    You have obtained an IAM access key with limited permissions.

    Run: terraform output -json leaked_credentials

    Configure the AWS CLI profile and find the flag.

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
    flag_bucket_name = aws_s3_bucket.flag.id
    flag_key         = aws_s3_object.flag.key
    user_arn         = aws_iam_user.attacker.arn
    detector_lambda  = aws_lambda_function.detector.function_name
  }
}
