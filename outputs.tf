output "api_url" {
  description = "Base URL of your API"
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "register_endpoint" {
  value = "${trimprefix(aws_apigatewayv2_stage.main.invoke_url, "/")}register"
}

output "login_endpoint" {
  value = "${trimprefix(aws_apigatewayv2_stage.main.invoke_url, "/")}logjn"
}

output "notes_endpoint" {
  value = "${trimprefix(aws_apigatewayv2_stage.main.invoke_url, "/")}notes"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.notes.name
}
