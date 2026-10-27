terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.6" }
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}

provider "kind" {}

# AWS provider is only exercised when target = "aws". For target = "local" we skip every
# credential/identity lookup so no AWS account is needed at all.
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = var.target != "aws"
  skip_requesting_account_id  = var.target != "aws"
  skip_metadata_api_check     = var.target != "aws"
  access_key                  = var.target != "aws" ? "unused" : null
  secret_key                  = var.target != "aws" ? "unused" : null
}
