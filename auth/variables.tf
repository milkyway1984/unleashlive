variable "user_email" {
  description = "Email address for the Cognito test user"
  type        = string
}

variable "user_password" {
  description = "Initial password for the Cognito test user"
  type        = string
  sensitive   = true
}
