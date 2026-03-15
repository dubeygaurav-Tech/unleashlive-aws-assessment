##############################################################
# Locals
##############################################################
locals {
  common_tags = {
    Project     = var.project
    Environment = "assessment"
    ManagedBy   = "Terraform"
    Owner       = var.candidate_email
  }
}