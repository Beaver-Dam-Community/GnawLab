#---------------------------------------
# SSM Parameter — Golden AMI pointer
#
# The Launch Template references this parameter via `resolve:ssm:...`,
# so whatever AMI ID is stored here is what the ASG will use when it
# launches new instances. This is the value the vulnerable Lambda
# rewrites on every schedule tick.
#
# Initial value: the freshly baked legitimate golden AMI.
# Post-attack value: whatever AMI the Lambda picked up — typically the
# attacker's public AMI sharing the configured name prefix.
#---------------------------------------
resource "aws_ssm_parameter" "golden_ami" {
  name        = local.ssm_parameter_name
  description = "Pointer to the current golden AMI for the ticketing tier. Updated by the golden-updater Lambda."
  type        = "String"
  data_type   = "aws:ec2:image"
  value       = aws_ami_from_instance.golden.id

  tags = merge(local.common_tags, {
    Name = "golden-ami-pointer-${local.scenario_id}"
  })

  # The Lambda will Overwrite this value on every tick. Ignore drift on `value`
  # so subsequent terraform applies do not fight with the Lambda's updates.
  lifecycle {
    ignore_changes = [value]
  }
}
