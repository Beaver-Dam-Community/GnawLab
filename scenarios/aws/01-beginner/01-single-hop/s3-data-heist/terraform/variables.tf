variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "This scenario must be deployed in us-east-1."
  }
}

variable "profile" {
  description = "AWS CLI profile to use for deployment"
  type        = string
  default     = "GnawLab"
}

variable "whitelist_ip" {
  description = "IP address to whitelist for S3 access (CIDR notation). Leave empty to auto-detect."
  type        = string
  default     = ""

  validation {
    condition     = var.whitelist_ip == "" || can(cidrhost(var.whitelist_ip, 0))
    error_message = "whitelist_ip must be a valid CIDR (e.g., 1.2.3.4/32) or empty for auto-detect."
  }
}

variable "flag_value" {
  description = "Flag value for the scenario"
  type        = string
  default     = "FLAG{s3_bucket_enum_and_exfil_complete}"
  sensitive   = true
}
