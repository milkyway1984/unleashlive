terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 backend – all values injected via -backend-config at terraform init
  # (see deploy.yml – TF_STATE_BUCKET secret)
  backend "s3" {
    key    = "unleash-assessment/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Primary region provider (us-east-1) - hosts Cognito
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Secondary region provider (eu-west-1)
provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

# ── Authentication (Cognito) ──────────────────────────────────────────────────
module "auth" {
  source = "./auth"

  providers = {
    aws = aws.us_east_1
  }

  user_email    = var.candidate_email
  user_password = var.cognito_test_password
}

# ── Networking – us-east-1 ────────────────────────────────────────────────────
module "networking_us" {
  source = "./modules/networking"

  providers = {
    aws = aws.us_east_1
  }

  region = "us-east-1"
  prefix = var.prefix
}

# ── Networking – eu-west-1 ────────────────────────────────────────────────────
module "networking_eu" {
  source = "./modules/networking"

  providers = {
    aws = aws.eu_west_1
  }

  region = "eu-west-1"
  prefix = var.prefix
}

# ── Compute – us-east-1 ───────────────────────────────────────────────────────
module "compute_us" {
  source = "./modules/compute"

  providers = {
    aws = aws.us_east_1
  }

  region                = "us-east-1"
  prefix                = var.prefix
  candidate_email       = var.candidate_email
  github_repo           = var.github_repo
  cognito_user_pool_arn = module.auth.user_pool_arn
  cognito_user_pool_id  = module.auth.user_pool_id
  cognito_client_id     = module.auth.client_id
  sns_topic_arn         = var.sns_topic_arn
  vpc_id                = module.networking_us.vpc_id
  public_subnet_ids     = module.networking_us.public_subnet_ids
}

# ── Compute – eu-west-1 ───────────────────────────────────────────────────────
module "compute_eu" {
  source = "./modules/compute"

  providers = {
    aws = aws.eu_west_1
  }

  region                = "eu-west-1"
  prefix                = var.prefix
  candidate_email       = var.candidate_email
  github_repo           = var.github_repo
  cognito_user_pool_arn = module.auth.user_pool_arn
  cognito_user_pool_id  = module.auth.user_pool_id
  cognito_client_id     = module.auth.client_id
  sns_topic_arn         = var.sns_topic_arn
  vpc_id                = module.networking_eu.vpc_id
  public_subnet_ids     = module.networking_eu.public_subnet_ids
}
