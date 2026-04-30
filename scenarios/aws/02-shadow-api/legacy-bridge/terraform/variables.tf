variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "scenario_name" {
  description = "Scenario identifier - used as a prefix for tagging/naming"
  type        = string
  default     = "legacy-bridge"
}

variable "availability_zone" {
  description = "Single AZ both subnets live in"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.10.2.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "flag_value" {
  description = "Flag baked into confidential/breach_notice.txt"
  type        = string
  default     = "FLAG{prime_financial_breach_2026__shadow_api_to_pii_vault}"
}