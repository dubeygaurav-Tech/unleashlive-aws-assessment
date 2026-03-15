##############################################################
# Module: auth
# Creates: Cognito User Pool, User Pool Client, Test User
# Region: us-east-1 (called once from root)
##############################################################

resource "aws_cognito_user_pool" "main" {
  
  name = "aws-assessment-user-pool"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  auto_verified_attributes = ["email"]

  # Schema – email required
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

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "aws-assessment-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Allow username/password auth so the test script can get a JWT
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # No client secret – simplifies SDK calls
  generate_secret = false

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  prevent_user_existence_errors = "ENABLED"
}

# Test user – password set via null_resource so it works on first apply
resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.test_user_email

  attributes = {
    email          = var.test_user_email
    email_verified = "true"
  }

  # Permanent password (avoids FORCE_CHANGE_PASSWORD on first login)
  temporary_password = var.test_user_temp_password
  message_action     = "SUPPRESS"

  lifecycle {
    ignore_changes = [temporary_password]
  }
}

# Set a permanent password so USER_PASSWORD_AUTH works without challenge
resource "null_resource" "set_permanent_password" {
  depends_on = [aws_cognito_user.test_user]

  provisioner "local-exec" {
    command = <<-EOT
      aws cognito-idp admin-set-user-password \
        --user-pool-id ${aws_cognito_user_pool.main.id} \
        --username ${var.test_user_email} \
        --password '${var.test_user_password}' \
        --permanent \
        --region us-east-1
    EOT
  }
}
