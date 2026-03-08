terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ── GitHub OIDC Provider ──────────────────────────────────────────────────────
# Only needs to exist once per AWS account. If it already exists, import it:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable – updated by GitHub, not us)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ── IAM Role assumed by GitHub Actions ───────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name = "github-actions-unleash-assessment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Scope to YOUR repo only – replace with your GitHub username
            "token.actions.githubusercontent.com:sub" = "repo:YOUR_GITHUB_USERNAME/aws-assessment:*"
          }
        }
      }
    ]
  })

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ── IAM Policy – what Terraform is allowed to provision ──────────────────────
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "terraform-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 – Terraform state backend
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      # Cognito
      {
        Effect   = "Allow"
        Action   = ["cognito-idp:*"]
        Resource = "*"
      },
      # Lambda
      {
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "*"
      },
      # API Gateway
      {
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "*"
      },
      # DynamoDB
      {
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = "*"
      },
      # ECS
      {
        Effect   = "Allow"
        Action   = ["ecs:*"]
        Resource = "*"
      },
      # EC2 / VPC networking
      {
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      # IAM – only roles/policies with the project prefix
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole"
        ]
        Resource = "arn:aws:iam::*:role/unleash-*"
      },
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:ListTagsLogGroup",
          "logs:TagLogGroup"
        ]
        Resource = "*"
      },
      # STS – needed for provider auth check
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "github_actions_role_arn" {
  description = "Paste this ARN into the GitHub Actions workflow and TF_ROLE_ARN secret"
  value       = aws_iam_role.github_actions.arn
}

variable "tf_state_bucket" {
  description = "S3 bucket name used for Terraform state"
  type        = string
}
