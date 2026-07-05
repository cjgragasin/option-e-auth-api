# =============================================================
# OPTION E — Auth-Protected REST API
# Cognito + API Gateway + Lambda (Python) + DynamoDB
# Region: ap-southeast-1
# =============================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# =============================================================
# COGNITO — handles user registration, login, and JWT tokens
# =============================================================

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  # Use email as the username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy — relaxed for learning
  password_policy {
    minimum_length    = 8
    require_uppercase = false
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
  }

  tags = { Name = "${var.project_name}-user-pool" }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # No client secret — keeps Lambda auth calls simple
  generate_secret = false

  # Allow username/password login
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# =============================================================
# DYNAMODB — stores notes
# =============================================================

resource "aws_dynamodb_table" "notes" {
  name         = "${var.project_name}-notes"
  billing_mode = "PAY_PER_REQUEST" # Cheapest — pay only per read/write, no idle cost

  hash_key  = "user_id"  # Partition key
  range_key = "note_id"  # Sort key

  attribute {
    name = "user_id"
    type = "S" # String
  }

  attribute {
    name = "note_id"
    type = "S"
  }

  tags = { Name = "${var.project_name}-notes" }
}

# =============================================================
# IAM ROLE — gives Lambda permission to use Cognito + DynamoDB
# =============================================================

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  # Trust policy — allows Lambda service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # DynamoDB access
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.notes.arn
      },
      {
        # Cognito access — needed for register (sign_up + admin_confirm)
        Effect = "Allow"
        Action = [
          "cognito-idp:SignUp",
          "cognito-idp:AdminConfirmSignUp",
          "cognito-idp:InitiateAuth"
        ]
        Resource = aws_cognito_user_pool.main.arn
      },
      {
        # CloudWatch Logs — so you can see Lambda logs
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# =============================================================
# LAMBDA — zip the Python code and deploy it
# =============================================================

# Zip the lambda folder automatically on every terraform apply
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "main" {
  function_name    = "${var.project_name}-api"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables — accessible inside handler.py via os.environ
  environment {
    variables = {
      REGION           = var.region
      TABLE_NAME       = aws_dynamodb_table.notes.name
      COGNITO_CLIENT_ID = aws_cognito_user_pool_client.main.id
      USER_POOL_ID     = aws_cognito_user_pool.main.id
    }
  }

  tags = { Name = "${var.project_name}-api" }
}

# =============================================================
# API GATEWAY — HTTP API with Cognito JWT authorizer
# =============================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

# JWT Authorizer — validates Bearer tokens issued by Cognito
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "cognito-authorizer"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# Integration — connects API Gateway to Lambda
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.main.invoke_arn
  payload_format_version = "2.0"
}

# Routes — PUBLIC (no auth)
resource "aws_apigatewayv2_route" "register" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /register"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "login" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /login"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Routes — PROTECTED (requires valid Cognito JWT)
resource "aws_apigatewayv2_route" "get_notes" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "create_note" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Stage — $default means the API is live at the root URL
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
