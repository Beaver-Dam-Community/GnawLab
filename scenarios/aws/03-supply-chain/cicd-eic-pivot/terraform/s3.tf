resource "aws_s3_bucket" "setup_files" {
  bucket        = "${local.scenario_name}-setup-${local.scenario_id}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${local.scenario_name}-setup-${local.scenario_id}" })
}

resource "aws_s3_bucket_public_access_block" "setup_files" {
  bucket                  = aws_s3_bucket.setup_files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "infra_main_tf" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/main.tf"
  source = "${path.module}/../assets/infra-repo/main.tf"
  etag   = filemd5("${path.module}/../assets/infra-repo/main.tf")
}

resource "aws_s3_object" "infra_variables_tf" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/variables.tf"
  source = "${path.module}/../assets/infra-repo/variables.tf"
  etag   = filemd5("${path.module}/../assets/infra-repo/variables.tf")
}

resource "aws_s3_object" "infra_atlantis_yaml" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/atlantis.yaml"
  source = "${path.module}/../assets/infra-repo/atlantis.yaml"
  etag   = filemd5("${path.module}/../assets/infra-repo/atlantis.yaml")
}

resource "aws_s3_object" "infra_security_review" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/SECURITY_REVIEW.md"
  source = "${path.module}/../assets/infra-repo/SECURITY_REVIEW.md"
  etag   = filemd5("${path.module}/../assets/infra-repo/SECURITY_REVIEW.md")
}

resource "aws_s3_object" "infra_adr_deploy" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/docs/adr/0003-deploy-pipeline.md"
  source = "${path.module}/../assets/infra-repo/docs/adr/0003-deploy-pipeline.md"
  etag   = filemd5("${path.module}/../assets/infra-repo/docs/adr/0003-deploy-pipeline.md")
}

resource "aws_s3_object" "infra_slack_export" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/docs/slack-2024-03.txt"
  source = "${path.module}/../assets/infra-repo/docs/slack-2024-03.txt"
  etag   = filemd5("${path.module}/../assets/infra-repo/docs/slack-2024-03.txt")
}

resource "aws_s3_object" "infra_readme" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/README.md"
  source = "${path.module}/../assets/infra-repo/README.md"
  etag   = filemd5("${path.module}/../assets/infra-repo/README.md")
}

resource "aws_s3_object" "infra_incident_2024_02" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/docs/incident-2024-02.md"
  source = "${path.module}/../assets/infra-repo/docs/incident-2024-02.md"
  etag   = filemd5("${path.module}/../assets/infra-repo/docs/incident-2024-02.md")
}

resource "aws_s3_object" "infra_env_example" {
  bucket = aws_s3_bucket.setup_files.id
  key    = "infra-repo/.env.example"
  source = "${path.module}/../assets/infra-repo/.env.example"
  etag   = filemd5("${path.module}/../assets/infra-repo/.env.example")
}
