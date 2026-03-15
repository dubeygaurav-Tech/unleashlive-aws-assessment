variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "aws-assessment"
}

variable "aws_region" {
  description = "AWS region where this module is deployed"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID (always in us-east-1)"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "candidate_sns_topic_arn" {
  description = "ARN of the Unleash candidate verification SNS topic"
  type        = string
  default     = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}

variable "candidate_email" {
  description = "Candidate email address for SNS payloads"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo URL for SNS payloads"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
