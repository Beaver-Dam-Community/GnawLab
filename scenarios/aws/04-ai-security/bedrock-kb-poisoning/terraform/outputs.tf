#---------------------------------------
# Scenario information
#---------------------------------------
output "scenario_info" {
  description = "Scenario information"
  value = {
    scenario_name = "bedrock-kb-poisoning"
    scenario_id   = local.scenario_id
    region        = var.region
    whitelist_ip  = local.whitelist_cidr
  }
}

#---------------------------------------
# Starting point: pre-seeded BPO editor (Kay)
#---------------------------------------
output "leaked_credentials" {
  description = "Pre-seeded BPO editor account (Kay) — the scenario starting credential."
  sensitive   = true
  value = {
    email    = aws_cognito_user.kay.username
    password = random_password.kay.result
    groups   = [aws_cognito_user_group.bpo_editor.name]
  }
}

output "owner_credentials" {
  description = "Pre-seeded seller_admin account (FitMall owner) — for reference / lateral comparison only."
  sensitive   = true
  value = {
    email    = aws_cognito_user.owner.username
    password = random_password.owner.result
    groups   = [aws_cognito_user_group.seller_admin.name]
  }
}

#---------------------------------------
# Endpoints used during the walkthrough
#---------------------------------------
output "console_url" {
  description = "TokTok-Support BPO console (sign in as Kay)."
  value       = "https://${aws_cloudfront_distribution.console.domain_name}/"
}

output "fitmall_storefront_url" {
  description = "Public-facing FitMall storefront mockup with the chat widget."
  value       = "https://${aws_cloudfront_distribution.console.domain_name}/fitmall/"
}

output "chat_api_url" {
  description = "Direct API Gateway /api/chat endpoint (also reachable via CloudFront /api/chat)."
  value       = "${aws_api_gateway_stage.prod.invoke_url}/api/chat"
}

output "user_pool_id" {
  description = "Cognito User Pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool app client ID (used by the SPA)."
  value       = aws_cognito_user_pool_client.spa.id
}

output "start_message" {
  description = "Starting point message"
  value       = <<-EOF

    ============================================================
                     BEDROCK KNOWLEDGE BASE POISONING
                          Scenario Ready
    ============================================================

    Console URL : https://${aws_cloudfront_distribution.console.domain_name}/

    Sign in as the BPO editor account:
      Email    : ${aws_cognito_user.kay.username}
      Password : (run `terraform output -json leaked_credentials`)
      Group    : bpo_editor

    Goal: recover the protected April 2026 customer export and
    extract the FLAG{customer_id} of the top VIP buyer.

    See ../walkthrough.md for the full attack path.

    ============================================================

  EOF
}

#---------------------------------------
# Verification (hidden)
#---------------------------------------
output "verification" {
  description = "For scenario verification only"
  sensitive   = true
  value = {
    workspace_bucket       = aws_s3_bucket.workspace.id
    document_catalog_table = aws_dynamodb_table.document_catalog.name
    agent_id               = aws_bedrockagent_agent.main.agent_id
    agent_alias_id         = aws_bedrockagent_agent_alias.prod.agent_alias_id
    knowledge_base_id      = aws_bedrockagent_knowledge_base.main.id
    customer_export_doc_id = local.customer_export_doc_id
    customer_export_s3_key = local.customer_export_s3_key
    expected_flag          = var.flag_value
  }
}
