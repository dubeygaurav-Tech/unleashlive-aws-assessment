

##############################################################
# Auth – Cognito (us-east-1 only)
##############################################################
module "auth" {
  source = "./modules/auth"

  providers = {
    aws = aws.us_east_1
  }

  test_user_email         = var.candidate_email
  test_user_temp_password = var.test_user_temp_password
  test_user_password      = var.test_user_password

  tags = local.common_tags
}

##############################################################
# Compute – us-east-1
##############################################################
module "compute_us_east_1" {
  source = "./modules/compute"

  providers = {
    aws = aws.us_east_1
  }

  project                 = var.project
  aws_region              = "us-east-1"
  vpc_cidr                = "10.0.0.0/16"
  cognito_user_pool_id    = module.auth.user_pool_id
  cognito_client_id       = module.auth.client_id
  candidate_email         = var.candidate_email
  github_repo             = var.github_repo
  candidate_sns_topic_arn = var.candidate_sns_topic_arn

  tags = local.common_tags
}

##############################################################
# Compute – eu-west-1
##############################################################
module "compute_eu_west_1" {
  source = "./modules/compute"

  providers = {
    aws = aws.eu_west_1
  }

  project                 = var.project
  aws_region              = "eu-west-1"
  vpc_cidr                = "10.1.0.0/16"
  cognito_user_pool_id    = module.auth.user_pool_id
  cognito_client_id       = module.auth.client_id
  candidate_email         = var.candidate_email
  github_repo             = var.github_repo
  candidate_sns_topic_arn = var.candidate_sns_topic_arn

  tags = local.common_tags
}
