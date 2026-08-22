###############################################################################
# providers.tf — Terraform + provider AWS
# State LOCAL (terraform.tfstate). Sin backend remoto para el reto.
###############################################################################
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  # backend "s3" { ... }   # (a futuro) mover el state a S3 + lock DynamoDB
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      ManagedBy   = "terraform"
      Reto        = "cobre-notifications"
    }
  }
}
