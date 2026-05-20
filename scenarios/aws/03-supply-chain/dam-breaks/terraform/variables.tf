variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "profile" {
  description = "AWS CLI profile to use for deployment"
  type        = string
  default     = "GnawLab"
}

variable "scenario_name" {
  description = "Scenario identifier — used as a prefix for tagging and naming"
  type        = string
  default     = "dam-breaks"
}

variable "availability_zone" {
  description = "Single AZ both subnets live in"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "CIDR block for the scenario VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the developer portal"
  type        = string
  default     = "t3.micro"
}

variable "whitelist_cidr" {
  description = "CIDR block allowed to access the developer portal. Use YOUR.PUBLIC.IP/32 to restrict access."
  type        = string
  default     = "0.0.0.0/0"
}

variable "flag_value" {
  description = "Flag stored in Secrets Manager — beaverpay/prod/flag"
  type        = string
  sensitive   = true
  default     = "flag{commit-clean-you-were-not}"
}
