output "cognito_user_pool_id" {
  description = "Cognito User Pool ID (us-east-1)"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.auth.client_id
}

output "api_endpoint_us_east_1" {
  description = "API Gateway URL – us-east-1"
  value       = module.compute_us_east_1.api_endpoint
}

output "api_endpoint_eu_west_1" {
  description = "API Gateway URL – eu-west-1"
  value       = module.compute_eu_west_1.api_endpoint
}

output "dynamodb_table_us_east_1" {
  description = "DynamoDB table name – us-east-1"
  value       = module.compute_us_east_1.dynamodb_table_name
}

output "dynamodb_table_eu_west_1" {
  description = "DynamoDB table name – eu-west-1"
  value       = module.compute_eu_west_1.dynamodb_table_name
}

output "ecs_cluster_us_east_1" {
  description = "ECS Cluster ARN – us-east-1"
  value       = module.compute_us_east_1.ecs_cluster_arn
}

output "ecs_cluster_eu_west_1" {
  description = "ECS Cluster ARN – eu-west-1"
  value       = module.compute_eu_west_1.ecs_cluster_arn
}
