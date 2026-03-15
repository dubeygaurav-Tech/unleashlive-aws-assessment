variable "test_user_email" {
  description = "Email address for the Cognito test user"
  type        = string
}

variable "test_user_temp_password" {
  description = "Temporary password (required by Cognito on creation)"
  type        = string
  sensitive   = true
}

variable "test_user_password" {
  description = "Permanent password set via admin-set-user-password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
