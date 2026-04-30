variable "region" {
  description = "AWS Region to deploy the scenario"
  type        = string
  default     = "us-east-1"
}

variable "beaver_id" {
  description = "Unique identifier for resource naming"
  type        = string
  default     = "cb-prod-01"
}

variable "scenario_name" {
  description = "Scenario name used for resource tagging"
  type        = string
  default     = "supply-chain-eic-pivot"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "gn_whitelist" {
  description = "List of trusted CIDR blocks allowed to access public-facing resources"
  type        = list(string)
  default     = []
}
