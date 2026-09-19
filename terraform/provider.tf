# infra/terraform/provider.tf

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }

  # Remote state in S3 + DynamoDB lock table
  # Before first apply: manually create the bucket and table
  #   aws s3api create-bucket --bucket defendarcade-tf-state \
  #     --region us-east-1 --create-bucket-configuration LocationConstraint=us-east-1
  #   aws s3api put-bucket-versioning --bucket defendarcade-tf-state \
  #     --versioning-configuration Status=Enabled
  #   aws dynamodb create-table --table-name defendarcade-terraform-locks \
  #     --attribute-definitions AttributeName=LockID,AttributeType=S \
  #     --key-schema AttributeName=LockID,KeyType=HASH \
  #     --billing-mode PAY_PER_REQUEST --region us-east-1
  backend "s3" {
    bucket       = "hardenthis-tf-state"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
