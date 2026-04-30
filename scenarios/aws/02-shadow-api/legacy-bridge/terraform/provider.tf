terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Scenario  = var.scenario_name
      ManagedBy = "beavergoat"
    }
  }
}

resource "random_string" "scenario_suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  suffix = random_string.scenario_suffix.result
  name   = var.scenario_name
}