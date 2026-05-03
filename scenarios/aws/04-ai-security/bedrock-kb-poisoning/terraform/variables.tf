#---------------------------------------
# Standard GnawLab variables
#---------------------------------------
variable "region" {
  description = "AWS region for resources (must be us-east-1 for Bedrock model + KB)"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "This scenario must be deployed in us-east-1 (Bedrock Agent + Knowledge Base availability)."
  }
}

variable "profile" {
  description = "AWS CLI profile to use for deployment"
  type        = string
  default     = "GnawLab"
}

variable "whitelist_ip" {
  description = "IP address (CIDR) allowed through CloudFront WAFv2 + API Gateway resource policy. Leave empty to auto-detect."
  type        = string
  default     = ""

  validation {
    condition     = var.whitelist_ip == "" || can(cidrhost(var.whitelist_ip, 0))
    error_message = "whitelist_ip must be a valid CIDR (e.g., 1.2.3.4/32) or empty for auto-detect."
  }
}

#---------------------------------------
# Scenario content variables
#---------------------------------------
variable "agent_model_id" {
  description = "Bedrock foundation model used by the chatbot Agent."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "embedding_model_id" {
  description = "Bedrock embedding model used by the Knowledge Base."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "bpo_email_domain" {
  description = <<-EOT
    Email domain treated as a trusted BPO partner. Pre-signup hook auto-confirms
    accounts on this domain and post-confirmation hook auto-attaches them to the
    `bpo_editor` Cognito group.
  EOT
  type        = string
  default     = "digitalcs.example.com"
}

variable "seller_email_domain" {
  description = "Email domain treated as the seller's own staff (auto-grouped to `seller_admin`)."
  type        = string
  default     = "fitmall.example.com"
}

variable "kay_email" {
  description = "Pre-seeded BPO editor account (Kay) used as the scenario starting credential."
  type        = string
  default     = "kay@digitalcs.example.com"
}

variable "owner_email" {
  description = "Pre-seeded seller_admin account for the FitMall workspace owner."
  type        = string
  default     = "owner@fitmall.example.com"
}

variable "flag_value" {
  description = "Expected FLAG{customer_id} for verification (matches the top row of the seeded CSV)."
  type        = string
  default     = "FLAG{FM-VIP-26Q2-T7K3}"
  sensitive   = true
}
