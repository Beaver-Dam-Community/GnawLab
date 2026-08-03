terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.44.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}
