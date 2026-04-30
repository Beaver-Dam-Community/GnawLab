resource "aws_iam_role" "gitlab_role" {
  name = "${var.scenario_name}-gitlab-role-${var.beaver_id}"

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

  tags = {
    Name = "${var.scenario_name}-gitlab-role-${var.beaver_id}"
  }
}

resource "aws_iam_role_policy" "gitlab_ssm_policy" {
  name = "${var.scenario_name}-gitlab-ssm-${var.beaver_id}"
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
  name = "${var.scenario_name}-gitlab-profile-${var.beaver_id}"
  role = aws_iam_role.gitlab_role.name
}

resource "aws_iam_role" "atlantis_role" {
  name = "${var.scenario_name}-atlantis-role-${var.beaver_id}"

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

  tags = {
    Name = "${var.scenario_name}-atlantis-role-${var.beaver_id}"
  }
}

resource "aws_iam_role_policy" "atlantis_policy" {
  name = "${var.scenario_name}-atlantis-policy-${var.beaver_id}"
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
  name = "${var.scenario_name}-atlantis-profile-${var.beaver_id}"
  role = aws_iam_role.atlantis_role.name
}

resource "aws_iam_role" "target_role" {
  name = "${var.scenario_name}-target-role-${var.beaver_id}"

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

  tags = {
    Name = "${var.scenario_name}-target-role-${var.beaver_id}"
  }
}

resource "aws_iam_instance_profile" "target_profile" {
  name = "${var.scenario_name}-target-profile-${var.beaver_id}"
  role = aws_iam_role.target_role.name
}
