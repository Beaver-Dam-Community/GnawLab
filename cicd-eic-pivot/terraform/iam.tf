resource "aws_iam_role" "gitlab_role" {
  name = local.gitlab_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = local.gitlab_role_name })
}

resource "aws_iam_role_policy" "gitlab_ssm_policy" {
  name = "${local.scenario_name}-gitlab-ssm-${local.scenario_id}"
  role = aws_iam_role.gitlab_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = aws_ssm_parameter.atlantis_gitlab_token.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "gitlab_profile" {
  name = "${local.scenario_name}-gitlab-profile-${local.scenario_id}"
  role = aws_iam_role.gitlab_role.name
}

resource "aws_iam_role" "atlantis_role" {
  name = local.atlantis_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = local.atlantis_role_name })
}

resource "aws_iam_role_policy" "atlantis_policy" {
  name = "${local.scenario_name}-atlantis-policy-${local.scenario_id}"
  role = aws_iam_role.atlantis_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "ec2-instance-connect:SendSSHPublicKey"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "ec2:osuser" = "ubuntu" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.atlantis_gitlab_token.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "atlantis_profile" {
  name = "${local.scenario_name}-atlantis-profile-${local.scenario_id}"
  role = aws_iam_role.atlantis_role.name
}

resource "aws_iam_role" "target_role" {
  name = local.target_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = local.target_role_name })
}

resource "aws_iam_instance_profile" "target_profile" {
  name = "${local.scenario_name}-target-profile-${local.scenario_id}"
  role = aws_iam_role.target_role.name
}
