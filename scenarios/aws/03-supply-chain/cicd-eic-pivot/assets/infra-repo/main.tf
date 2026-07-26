provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "corporate_data" {
  bucket = "beaver-corp-data-storage-${var.environment}"

  tags = {
    ManagedBy   = "Atlantis"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "data_protection" {
  bucket = aws_s3_bucket.corporate_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────────────────────────────────────
# PLAT-1203 | Deploy trigger -- temporary, not production-grade
# ──────────────────────────────────────────────────────────────────────────────
#
# Context:
#   We moved infra to Terraform + Atlantis for GitOps. The app itself still runs
#   on a plain EC2 instance and deploys via a legacy deploy.sh script.
#   No containers yet. No rolling update mechanism. Just EC2 + shell.
#
#   When we adopted GitOps, we hit an immediate problem: Atlantis can reprovision
#   infra, but it can't run deploy.sh on the live instance automatically.
#   We needed a bridge until we containerize properly.
#
# What we evaluated:
#
#   user_data:
#     Runs exactly once -- at first boot. Useless for repeated deploys.
#     We deploy 3–5 times a day. Reprovisioning the instance on each deploy
#     was not acceptable.
#
#   Ansible:
#     Right tool for this. But setting up a controller, writing playbooks,
#     and onboarding the team was more setup than we could afford that sprint.
#     We needed to ship by end of week.
#
#   AWS CodeDeploy:
#     Proper solution long-term. But it requires installing the CodeDeploy agent
#     on every target instance and maintaining a buildspec per application.
#     We don't have the bandwidth to build that pipeline while also launching
#     the product. Deferred to PLAT-1203.
#
#   EC2 Instance Connect (current, temporary):
#     Injects a short-lived SSH key (60s TTL) via AWS API, runs the command, key
#     expires automatically. No persistent key on disk. Felt safer than keeping
#     a .pem file around. Atlantis needs ec2-instance-connect:SendSSHPublicKey
#     in its IAM role. We scoped it to Resource: * because instances get replaced
#     during maintenance and we didn't want to chase ARNs every time.
#
#     Yes, we know this gives Atlantis broad SSH access across the account.
#     It's tracked. See SECURITY_REVIEW.md and docs/adr/0003-deploy-pipeline.md.
#     We're moving to CodeDeploy in Q1 and will clean up the role then.
#
#   If you're reading this after Q1 and the role still has Resource: * -- fix it.
# ──────────────────────────────────────────────────────────────────────────────
resource "null_resource" "deploy_trigger" {
  triggers = {
    app_version = var.app_version
  }

  provisioner "local-exec" {
    command = <<-EOF
      mssh -o StrictHostKeyChecking=no ubuntu@${var.app_instance_id} \
        "cd /app && git pull origin main && bash deploy.sh"
    EOF
  }
}
