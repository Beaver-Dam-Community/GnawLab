variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "This scenario must be deployed in us-east-1."
  }
}

variable "profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "GnawLab"
}

variable "whitelist_ip" {
  description = "IP address to whitelist (CIDR format). Leave empty for auto-detection."
  type        = string
  default     = ""

  validation {
    condition     = var.whitelist_ip == "" || can(cidrhost(var.whitelist_ip, 0))
    error_message = "whitelist_ip must be a valid CIDR block (e.g., 1.2.3.4/32)."
  }
}

variable "flag_value" {
  description = "Flag value for the scenario"
  type        = string
  default     = "FLAG{ecs_task_role_to_secrets_manager_pwned}"
  sensitive   = true
}
