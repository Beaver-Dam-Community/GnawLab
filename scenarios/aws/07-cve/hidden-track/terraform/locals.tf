resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  suffix        = random_string.suffix.result
  scenario_name = "gnawlab-beaversound"

  uploads_bucket_name  = "beaversound-uploads-${local.suffix}"
  vault_bucket_name    = "beaversound-vault-${local.suffix}"
  lambda_function_name = "beaversound-process-upload-${local.suffix}"
  lambda_role_name     = "beaversound-lambda-exec-${local.suffix}"
  lambda_layer_name    = "beaversound-exiftool-${local.suffix}"
  portal_role_name     = "beaversound-portal-role-${local.suffix}"
  portal_profile_name  = "beaversound-portal-profile-${local.suffix}"
  portal_policy_name   = "beaversound-portal-policy-${local.suffix}"
  lambda_policy_name   = "beaversound-lambda-policy-${local.suffix}"
  portal_sg_name       = "${local.scenario_name}-portal-sg-${local.suffix}"
  vpc_name             = "${local.scenario_name}-vpc-${local.suffix}"
  gd_role_name         = "beaversound-guardduty-role-${local.suffix}"

  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  tracklist_content = <<-TXT
    [CONFIDENTIAL — DO NOT DISTRIBUTE]

    Artist : Maya Arden
    Album  : Neon Fault Line
    Label  : Stellar Records

    01. Static Dreams
    02. Glass Meridian
    03. After the Signal
    04. Neon Fault Line
    05. Low Orbit
    06. Satellite (feat. Kian)
    07. Empty Frequency
    08. Hidden Track

    ---
    internal-id: ${var.flag_value}
    TXT

  common_tags = {
    Scenario    = "hidden-track"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    Suffix      = local.suffix
  }
}
