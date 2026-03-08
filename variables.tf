variable "candidate_email" {
  description = "Candidate email – used for Cognito test user and SNS payloads"
  type        = string
  default     = "your_email@example.com"
}

variable "cognito_test_password" {
  description = "Initial password for the Cognito test user"
  type        = string
  sensitive   = true
  default     = "TempPass123!"
}

variable "github_repo" {
  description = "GitHub repo URL for SNS payload"
  type        = string
  default     = "https://github.com/YOUR_GITHUB_USERNAME/aws-assessment"
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "unleash"
}

variable "sns_topic_arn" {
  description = "Unleash live candidate verification SNS topic ARN"
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}
