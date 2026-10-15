terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  # Every resource Terraform creates gets these tags. Doc 13 uses the
  # Project tag to prove nothing was left running after teardown.
  default_tags {
    tags = {
      Project   = "aws-cloud-homelab"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
