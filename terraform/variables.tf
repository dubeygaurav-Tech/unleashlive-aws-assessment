variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "aws-assessment"
}

variable "candidate_email" {
  description = "Your email address (used for Cognito test user and SNS payloads)"
  type        = string
  default     = "dubeygaurav.tech@gmail.com"
}

variable "test_user_temp_password" {
  description = "Temporary Cognito password (must satisfy the pool policy)"
  type        = string
  sensitive   = true
}

variable "test_user_password" {
  description = "Permanent Cognito password set via admin-set-user-password"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository URL for SNS payloads"
  type        = string
  default     = "https://github.com/dubeygaurav-Tech/unleashlive-aws-assessment"
}

variable "candidate_sns_topic_arn" {
  description = "ARN of the Unleash candidate verification SNS topic"
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}
