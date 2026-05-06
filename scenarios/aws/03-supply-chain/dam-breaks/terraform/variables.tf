variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
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
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "whitelist_cidr" {
  description = "CIDR blocks allowed to access the developer portal. Defaults to open access."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "flag_value" {
  description = "Flag stored in Secrets Manager — beaverpay/prod/flag"
  type        = string
  default     = "FLAG{th3_c0mm1t_w4s_cl34n_but_y0u_w3r3_n0t}"
}
