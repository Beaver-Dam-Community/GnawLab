terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
  default_tags {
    tags = {
      Scenario    = var.scenario_name
      Project     = "GnawLab"
      Environment = "training"
      ManagedBy   = "terraform"
      ScenarioID  = random_id.scenario_suffix.hex
    }
  }
}
