data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway_app_role_iam" {
  name               = "${local.name}-Gateway-App-Role-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json

  tags = {
    Name = "Gateway-App-Role"
    Tier = "entrypoint"
  }
}

resource "aws_iam_role_policy_attachment" "gateway_app_role_ssm" {
  role       = aws_iam_role.gateway_app_role_iam.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gateway_app_profile" {
  name = "${local.name}-Gateway-App-Profile-${local.suffix}"
  role = aws_iam_role.gateway_app_role_iam.name
}

resource "aws_iam_role" "shadow_api_role_iam" {
  name               = "${local.name}-Shadow-API-Role-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json

  tags = {
    Name = "Shadow-API-Role"
    Tier = "internal-data-plane"
  }
}

resource "aws_iam_role_policy_attachment" "shadow_api_role_ssm" {
  role       = aws_iam_role.shadow_api_role_iam.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "shadow_api_role_s3_policy_doc" {
  statement {
    sid    = "AllowDiscoverBuckets"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowCheckOwnRolePermissions"
    effect    = "Allow"
    actions   = [
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
    ]
    resources = [aws_iam_role.shadow_api_role_iam.arn]
  }

  statement {
    sid       = "AllowListPiiVault"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.prime_pii_vault_s3.arn]
  }

  statement {
    sid       = "AllowReadPiiVaultObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.prime_pii_vault_s3.arn}/*"]
  }
}

resource "aws_iam_role_policy" "shadow_api_role_s3_policy" {
  name   = "${local.name}-shadow-api-s3-${local.suffix}"
  role   = aws_iam_role.shadow_api_role_iam.id
  policy = data.aws_iam_policy_document.shadow_api_role_s3_policy_doc.json
}

resource "aws_iam_instance_profile" "shadow_api_profile" {
  name = "${local.name}-Shadow-API-Profile-${local.suffix}"
  role = aws_iam_role.shadow_api_role_iam.name
}