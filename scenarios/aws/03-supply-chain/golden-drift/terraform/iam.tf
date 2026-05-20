#============================================================
# 1. Attacker IAM User (Leaked Credentials)
#============================================================
# Read-only baseline. The attacker can:
#   - Enumerate IAM / EC2 / ASG / Lambda / SSM / Secrets Manager metadata
#   - Read the Lambda's source code (to discover the missing Owners filter)
#   - Read CloudWatch Logs (to watch the Lambda's behavior)
# The attacker CANNOT:
#   - Write to SSM, modify the Launch Template, alter the ASG, or read the
#     flag secret directly. Every escalation must go through the WhoAMI
#     attack path (publish a public AMI in another account and wait for the
#     vulnerable Lambda to pick it up).
#============================================================
resource "aws_iam_user" "attacker" {
  name          = local.attacker_user_name
  path          = "/gnawlab/"
  force_destroy = true

  tags = merge(local.common_tags, {
    Description = "Simulated leaked attacker user for golden-drift scenario"
  })
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

resource "aws_iam_user_policy" "attacker_readonly" {
  name = local.attacker_policy_name
  user = aws_iam_user.attacker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IdentityVerification"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid    = "SelfEnumeration"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUserPolicies",
          "iam:GetUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:ListGroupsForUser",
          "iam:ListGroupPolicies",
          "iam:ListAttachedGroupPolicies",
          "iam:GetGroupPolicy",
        ]
        Resource = [
          aws_iam_user.attacker.arn,
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/*",
        ]
      },
      {
        Sid    = "IamMetadataReconnaissance"
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
        ]
        Resource = "*"
      },
      {
        Sid    = "InfraReconnaissance"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ssm:GetParameter",
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaCodeInspection"
        Effect = "Allow"
        Action = [
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
        ]
        Resource = "*"
      },
    ]
  })
}

#============================================================
# 2. EC2 Instance Profile — used by every ASG-launched instance
#============================================================
# Both the legitimate and the malicious AMI inherit this profile because
# the Launch Template references it directly.
#
# The instance can read the flag secret. That is intentional — the
# legitimate ticketing app might legitimately want to fetch app secrets,
# but the malicious AMI abuses the same privilege to exfiltrate the flag.
#============================================================
resource "aws_iam_role" "instance" {
  name = local.instance_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "instance_read_flag_secret" {
  name = "${local.scenario_name}-instance-read-flag-${local.scenario_id}"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadFlagSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = aws_secretsmanager_secret.flag.arn
      },
    ]
  })
}

# Optional managed policy attached so the instance can be reached via
# SSM Session Manager if the operator needs to debug. Not used by the
# scenario attack path itself.
resource "aws_iam_role_policy_attachment" "instance_ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = local.instance_profile_name
  role = aws_iam_role.instance.name
}

#============================================================
# 3. Lambda Execution Role — for the vulnerable golden-AMI updater
#============================================================
# The Lambda needs:
#   - ec2:DescribeImages  — to look up AMIs by name
#   - ssm:PutParameter    — to update the golden AMI pointer
#   - logs:*              — basic Lambda logging
#============================================================
resource "aws_iam_role" "lambda" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_updater" {
  name = "${local.scenario_name}-updater-policy-${local.scenario_id}"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeImages"
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
        ]
        # describe_images requires Resource "*" — it is a list operation.
        Resource = "*"
      },
      {
        Sid    = "UpdateGoldenAmiParameter"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
        ]
        Resource = aws_ssm_parameter.golden_ami.arn
      },
    ]
  })
}
