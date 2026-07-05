# Auth-Protected REST API with Terraform

A serverless REST API built with AWS and deployed using Terraform. Features user authentication via Cognito JWT tokens and per-user data storage in DynamoDB.

## Architecture

```
Client (curl / Postman / Frontend)
    │
    ├── POST /register  ──▶  Lambda ──▶ Cognito (create user)
    ├── POST /login     ──▶  Lambda ──▶ Cognito (returns JWT token)
    │
    │   [Authorization: Bearer <token>]
    │
    ├── GET  /notes     ──▶  API Gateway (validates JWT) ──▶ Lambda ──▶ DynamoDB
    └── POST /notes     ──▶  API Gateway (validates JWT) ──▶ Lambda ──▶ DynamoDB
```

## Stack

| Service | Purpose |
|---|---|
| **Terraform** | Infrastructure as Code — provisions all AWS resources |
| **AWS Cognito** | User authentication, JWT token issuance |
| **AWS API Gateway** | HTTP API with JWT authorizer |
| **AWS Lambda** | Serverless business logic (Python 3.12) |
| **AWS DynamoDB** | NoSQL database, per-user note storage |
| **AWS IAM** | Least-privilege permissions for Lambda |

## Features

- User registration and login via Cognito
- JWT token-based authentication
- Protected routes — blocked without a valid token
- Per-user data isolation in DynamoDB
- Fully serverless — no servers to manage
- Pay-per-use — near zero cost at low traffic

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- AWS account with IAM permissions for Lambda, Cognito, DynamoDB, API Gateway

## Deploy

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/option-e-auth-api
cd option-e-auth-api

# 2. Create your tfvars (not committed to git)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize and deploy
terraform init
terraform plan
terraform apply
```

After apply, Terraform outputs your API endpoints:
```
api_url           = "https://xxxxxxxxxx.execute-api.ap-southeast-1.amazonaws.com"
register_endpoint = "https://xxxxxxxxxx.execute-api.ap-southeast-1.amazonaws.com/register"
login_endpoint    = "https://xxxxxxxxxx.execute-api.ap-southeast-1.amazonaws.com/login"
notes_endpoint    = "https://xxxxxxxxxx.execute-api.ap-southeast-1.amazonaws.com/notes"
```

## API Usage

### Register
```bash
curl -X POST https://<api_url>/register \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "MyPass123"}'
```

### Login
```bash
curl -X POST https://<api_url>/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "MyPass123"}'

# Returns: { "access_token": "eyJ..." }
```

### Create a Note (protected)
```bash
curl -X POST https://<api_url>/notes \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"content": "My first note"}'
```

### Get Notes (protected)
```bash
curl -X GET https://<api_url>/notes \
  -H "Authorization: Bearer <access_token>"
```

### Unauthorized request (no token)
```bash
curl -X GET https://<api_url>/notes
# Returns: {"message": "Unauthorized"} 401
```

## Project Structure

```
option-e-auth-api/
├── main.tf           # All AWS resources
├── variables.tf      # Variable declarations
├── outputs.tf        # API endpoint URLs
├── terraform.tfvars  # Your values (gitignored)
├── lambda/
│   └── handler.py    # Python Lambda function
└── README.md
```

## Teardown

```bash
terraform destroy
```

## Cost

Near zero for learning/testing. All services charge per use with no idle cost:
- Lambda: first 1M requests/month free
- DynamoDB: PAY_PER_REQUEST mode
- Cognito: first 50,000 MAUs free
- API Gateway: ~$1 per million requests