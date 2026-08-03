resource "aws_instance" "vulnboard" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.vulnboard.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true

  # IMDSv2 enforced, hop_limit = 1.
  # This matches AWS's recommended hardening and the configuration the
  # platform team rolled out in early 2024. The scenario's escape relies on
  # the docker.sock mount bypassing this control (a host-network container
  # spawned via the socket inherits hop_limit = 1 reachability).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = local.ec2_name
    Role = "vulnboard-host"
  }
}
