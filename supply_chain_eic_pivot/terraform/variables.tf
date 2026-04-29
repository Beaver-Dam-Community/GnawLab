variable "region" {
  description = "AWS Region to deploy the scenario"
  type        = string
  default     = "us-east-1"
}

variable "beaver_id" {
  description = "Unique identifier for CloudBeaver resources"
  type        = string
  default     = "cb-prod-01" # 예시 값
}

variable "scenario_name" {
  description = "Scenario name for tagging"
  type        = string
  default     = "supply-chain-eic-pivot"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (GitLab, Bastion)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (Target Server)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "cg_whitelist" {
  description = "User's public IP whitelist (CloudGoat compatible name)"
  type        = list(string)
  default     = []
}
