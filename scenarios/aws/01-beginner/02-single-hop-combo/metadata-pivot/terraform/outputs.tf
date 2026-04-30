#---------------------------------------
# Scenario Information
#---------------------------------------
output "scenario_info" {
  description = "Scenario information"
  value = {
    scenario_name = "metadata-pivot"
    scenario_id   = local.scenario_id
    region        = var.region
    whitelist_ip  = local.whitelist_cidr
  }
}

#---------------------------------------
# Starting Point
#---------------------------------------
output "web_app_url" {
  description = "URL of the vulnerable web application"
  value       = "http://${aws_instance.web.public_ip}"
}

output "start_message" {
  description = "Starting point message"
  value       = <<-EOF

    ============================================================
                       METADATA PIVOT
                       Scenario Ready
    ============================================================

    You discovered a web application at Beaver Dam Bank.

    Target URL: http://${aws_instance.web.public_ip}

    The bank offers a Custom Card Designer feature.
    Find the flag hidden in cloud storage!

    Note: Wait 1-2 minutes for EC2 initialization.

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
    bucket_name   = aws_s3_bucket.data.id
    flag_key      = aws_s3_object.flag.key
    ec2_role_arn  = aws_iam_role.ec2_role.arn
    ec2_role_name = aws_iam_role.ec2_role.name
    ec2_public_ip = aws_instance.web.public_ip
  }
}
