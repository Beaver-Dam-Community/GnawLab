#---------------------------------------
# Launch Template
#
# Critical detail: ImageId references the SSM parameter via `resolve:ssm:...`
# rather than a hard-coded AMI ID. EC2 resolves this string at RunInstances
# time, so whatever value is currently stored in the SSM parameter becomes
# the AMI used for the new instance.
#
# Normal operation:  resolve -> ami-CLEAN (the baked golden AMI)
# After WhoAMI attack: resolve -> ami-EVIL (the attacker's public AMI that
#                                            the vulnerable Lambda picked up)
#---------------------------------------
resource "aws_launch_template" "app" {
  name          = local.launch_template_name
  image_id      = "resolve:ssm:${local.ssm_parameter_name}"
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  monitoring {
    enabled = true
  }

  metadata_options {
    # IMDSv2 required — discourages SSRF-style credential theft from outside
    # the scenario's main attack path.
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.scenario_name}-instance-${local.scenario_id}"
    })
  }

  tags = merge(local.common_tags, {
    Name = local.launch_template_name
  })

  # Avoid forcing a new launch template version every time terraform refresh
  # resolves the SSM parameter to a different concrete AMI.
  lifecycle {
    ignore_changes = [image_id]
  }

  depends_on = [aws_ssm_parameter.golden_ami]
}

#---------------------------------------
# Auto Scaling Group
#
# Sized intentionally small so load testing reliably triggers scale-out:
#   - min/desired = 1 (only one running instance under normal traffic)
#   - max         = 3 (cap to keep lab cost low; scale-out has somewhere to go)
#   - cooldown    = 60s (default 300s is too slow for a lab)
#---------------------------------------
resource "aws_autoscaling_group" "app" {
  name                      = local.asg_name
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 60
  default_cooldown          = 60

  min_size         = 1
  desired_capacity = 1
  max_size         = 2

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.scenario_name}-asg-instance-${local.scenario_id}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Scenario"
    value               = "golden-drift"
    propagate_at_launch = true
  }

  tag {
    key                 = "ScenarioID"
    value               = local.scenario_id
    propagate_at_launch = true
  }
}

#---------------------------------------
# Target Tracking Scaling Policy
#
# Target average CPU = 30%. Set low so that an external load test reliably
# pushes the t2.micro into scale-out territory within ~1-2 minutes.
#---------------------------------------
resource "aws_autoscaling_policy" "cpu_target" {
  name                      = "${local.scenario_name}-cpu-target-${local.scenario_id}"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 60

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 30.0
    disable_scale_in = false
  }
}
