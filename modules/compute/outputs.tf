output "api_endpoint" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  value = aws_apigatewayv2_api.main.id
}

output "greeter_lambda_arn" {
  value = aws_lambda_function.greeter.arn
}

output "dispatcher_lambda_arn" {
  value = aws_lambda_function.dispatcher.arn
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.greeting_logs.name
}
