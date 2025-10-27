################################################################################
# File: terraform/providers.tf
################################################################################

terraform {
  required_version = ">= 1.13.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# AWS Provider - Deploy to dev account
provider "aws" {
  region = var.aws_region

  # Assume role in DEV account to deploy resources

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}