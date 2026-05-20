# The flag value lives in SSM Parameter Store (SecureString) and is injected
# into the flag-vault container via the ECS task definition's `secrets` field.
#
# This deliberately avoids putting the literal flag in the task definition's
# `environment` array, where it would be visible to anyone holding the
# `ecs:DescribeTaskDefinition` action — i.e. the very IAM role the attacker
# enumerates in Phase 7. With SecureString the task definition only reveals
# the parameter ARN; pulling the value requires ssm:GetParameters on that
# specific ARN, which the EC2 (app) role does NOT have. The only intended
# path to the flag remains `ecs:ExecuteCommand` into the running container.

resource "aws_ssm_parameter" "flag" {
  name        = "/gnawlab/codejudge/${local.scenario_id}/flag"
  description = "code-judge-escape flag (intentionally vulnerable training lab)"
  type        = "SecureString"
  value       = local.flag_value

  tags = {
    Name = "${local.scenario_name}-flag-${local.scenario_id}"
  }
}
