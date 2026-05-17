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
  description = "IP address to whitelist for ALB access (CIDR notation). Leave empty to auto-detect."
  type        = string
  default     = ""

  validation {
    condition     = var.whitelist_ip == "" || can(cidrhost(var.whitelist_ip, 0))
    error_message = "whitelist_ip must be a valid CIDR (e.g., 1.2.3.4/32) or empty for auto-detect."
  }
}

variable "flag_value" {
  description = "Flag value stored in Secrets Manager"
  type        = string
  default     = "FLAG{whoami_image_name_confusion_complete}"
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for the ASG. t2.micro is intentionally weak so load testing triggers scale-out quickly."
  type        = string
  default     = "t2.micro"
}
