# infra-repo/variables.tf

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "app_version" {
  description = "Application version tag -- changing this value triggers a redeploy via EC2 Instance Connect"
  type        = string
  default     = "v1.0.0"
}

variable "app_instance_id" {
  description = "EC2 instance ID of the application server to deploy to (overridden in production via tfvars)"
  type        = string
  default     = "i-0placeholder00000000"
}
