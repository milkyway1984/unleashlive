variable "region" {
  description = "AWS region for this compute stack"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "candidate_email" {
  description = "Candidate email for SNS payloads"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo URL for SNS payload"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool in us-east-1"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool in us-east-1"
  type        = string
  default     = ""
}

variable "cognito_client_id" {
  description = "Cognito App Client ID"
  type        = string
  default     = ""
}

variable "sns_topic_arn" {
  description = "Unleash live SNS topic ARN"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy resources into"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}
