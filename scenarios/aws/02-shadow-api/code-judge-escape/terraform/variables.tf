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
  description = "IP address to whitelist (CIDR format). Leave empty for auto-detection via ifconfig.co."
  type        = string
  default     = ""

  validation {
    condition     = var.whitelist_ip == "" || can(cidrhost(var.whitelist_ip, 0))
    error_message = "whitelist_ip must be a valid CIDR block (e.g., 1.2.3.4/32)."
  }
}

variable "flag_value" {
  description = "Flag value placed in the private Fargate task filesystem"
  type        = string
  default     = "FLAG{pickle_to_docker_sock_to_imds_to_ecs_exec}"
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type for the VulnBoard host"
  type        = string
  default     = "t3.small"
}
