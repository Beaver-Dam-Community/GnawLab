# 1. Atlantis 러너를 위한 IAM Role
resource "aws_iam_role" "atlantis_role" {
  name = "${var.scenario_name}-atlantis-role-${var.beaver_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.scenario_name}-atlantis-role-${var.beaver_id}"
  }
}

# 2. 과도한 권한 부여 (시나리오 핵심 취약점)
resource "aws_iam_role_policy" "atlantis_policy" {
  name = "${var.scenario_name}-atlantis-emergency-access-${var.beaver_id}"
  role = aws_iam_role.atlantis_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 1) 정찰 권한
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      # 2) 피벗 포인트: EIC SendKey
      {
        Action   = "ec2-instance-connect:SendSSHPublicKey"
        Effect   = "Allow"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = {
            "ec2:osuser" = "ubuntu"
          }
        }
      }
    ]
  })
}

# 3. EC2 인스턴스에 IAM Role을 연결하기 위한 Profile
resource "aws_iam_instance_profile" "atlantis_profile" {
  name = "${var.scenario_name}-atlantis-profile-${var.beaver_id}"
  role = aws_iam_role.atlantis_role.name
}

# 4. Target Server를 위한 제한적 IAM Role
resource "aws_iam_role" "target_role" {
  name = "${var.scenario_name}-target-role-${var.beaver_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "target_profile" {
  name = "${var.scenario_name}-target-profile-${var.beaver_id}"
  role = aws_iam_role.target_role.name
}
