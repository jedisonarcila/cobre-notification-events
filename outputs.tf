###############################################################################
# outputs.tf
###############################################################################
output "api_endpoint" {
  description = "URL base de la API self-service"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "cognito_token_url" {
  description = "Endpoint de tokens M2M (client_credentials)"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/token"
}

output "cognito_m2m_client_id" {
  value = aws_cognito_user_pool_client.m2m.id
}

output "queue_raw_events_url" {
  value = aws_sqs_queue.raw_events.url
}

output "queue_deliveries_url" {
  value = aws_sqs_queue.deliveries.url
}

output "table_notification_events" {
  value = aws_dynamodb_table.notification_events.name
}

output "table_subscriptions" {
  value = aws_dynamodb_table.subscriptions.name
}

output "ecr_repositories" {
  description = "URLs de los repos ECR (push de imágenes)"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "archive_bucket" {
  value = aws_s3_bucket.archive.bucket
}
