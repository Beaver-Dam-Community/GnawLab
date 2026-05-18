resource "aws_instance" "portal" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.portal.id]
  iam_instance_profile   = aws_iam_instance_profile.portal.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  user_data_base64          = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    uploads_bucket  = aws_s3_bucket.uploads.id
    lambda_function = aws_lambda_function.process_upload.function_name
    aws_region      = var.region
  }))
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name        = "${local.scenario_name}-portal-${local.suffix}"
    Description = "BeaverSound artist portal — ExifTool pipeline entry point"
    Role        = "portal"
  })

  depends_on = [
    aws_internet_gateway.main,
    aws_iam_instance_profile.portal,
    aws_iam_role_policy.portal_policy,
    aws_lambda_function.process_upload
  ]
}
