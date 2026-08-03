resource "aws_s3_bucket" "uploads" {
  bucket        = local.uploads_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = local.uploads_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = aws_s3_bucket.uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "vault" {
  bucket        = local.vault_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = local.vault_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "vault" {
  bucket                  = aws_s3_bucket.vault.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "vault" {
  bucket = aws_s3_bucket.vault.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "master_take2" {
  bucket  = aws_s3_bucket.vault.id
  key     = "unreleased_master_take_2.mp3"
  content = "# BeaverSound Vault\n# unreleased_master_take_2.mp3 — placeholder\n"

  tags = merge(local.common_tags, {
    Classification = "CONFIDENTIAL"
    Artist         = "Maya Arden"
  })

  depends_on = [aws_s3_bucket_versioning.vault]
}

resource "aws_s3_object" "session_raw" {
  bucket  = aws_s3_bucket.vault.id
  key     = "session_recordings_raw.mp3"
  content = "# BeaverSound Vault\n# session_recordings_raw.mp3 — placeholder\n"

  tags = merge(local.common_tags, {
    Classification = "CONFIDENTIAL"
    Artist         = "Maya Arden"
  })

  depends_on = [aws_s3_bucket_versioning.vault]
}

resource "aws_s3_object" "tracklist" {
  bucket  = aws_s3_bucket.vault.id
  key     = "tracklist.txt"
  content = local.tracklist_content

  tags = merge(local.common_tags, {
    Classification = "TOP SECRET"
    Artist         = "Maya Arden"
    Album          = "Neon Fault Line"
  })

  depends_on = [aws_s3_bucket_versioning.vault]
}

resource "null_resource" "delete_tracklist" {
  triggers = {
    version_id = aws_s3_object.tracklist.version_id
    bucket     = aws_s3_bucket.vault.id
  }

  provisioner "local-exec" {
    command = "aws s3 rm s3://${aws_s3_bucket.vault.id}/tracklist.txt --profile ${var.profile} --region ${var.region}"
  }

  depends_on = [aws_s3_object.tracklist]
}
