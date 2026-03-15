output "api_endpoint" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.greeting_logs.name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.publisher.arn
}

output "greeter_lambda_arn" {
  description = "Greeter Lambda ARN"
  value       = aws_lambda_function.greeter.arn
}

output "dispatcher_lambda_arn" {
  description = "Dispatcher Lambda ARN"
  value       = aws_lambda_function.dispatcher.arn
}
