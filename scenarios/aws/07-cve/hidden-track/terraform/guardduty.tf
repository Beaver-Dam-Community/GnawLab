resource "aws_guardduty_detector" "main" {
  enable = true

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-detector-${local.suffix}"
  })
}

resource "aws_guardduty_malware_protection_plan" "uploads" {
  role = aws_iam_role.guardduty_malware.arn

  protected_resource {
    s3_bucket {
      bucket_name = aws_s3_bucket.uploads.id
    }
  }

  actions {
    tagging {
      status = "ENABLED"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.scenario_name}-malware-plan-${local.suffix}"
  })

  depends_on = [
    aws_guardduty_detector.main,
    aws_iam_role_policy.guardduty_malware_policy
  ]
}
