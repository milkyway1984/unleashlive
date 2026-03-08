terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ── Cognito User Pool ─────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "main" {
  name = "unleash-live-user-pool"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # MFA – off for assessment simplicity
  mfa_configuration = "OFF"

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # User attribute schema
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  tags = {
    Project     = "unleash-assessment"
    ManagedBy   = "terraform"
  }
}

# ── App Client ────────────────────────────────────────────────────────────────
resource "aws_cognito_user_pool_client" "app" {
  name         = "unleash-live-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Enable USER_PASSWORD_AUTH for the test script (programmatic login)
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # No client secret – simpler for test script auth
  generate_secret = false

  # Token validity
  # hours
  access_token_validity  = 1   
  # hours
  id_token_validity      = 1   
  # days
  refresh_token_validity = 30  

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# ── Test User ─────────────────────────────────────────────────────────────────
resource "aws_cognito_user" "test" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.user_email

  # Set a permanent password (skip FORCE_CHANGE_PASSWORD flow)
  temporary_password   = var.user_password
  message_action       = "SUPPRESS"

  attributes = {
    email          = var.user_email
    email_verified = true
  }
}
