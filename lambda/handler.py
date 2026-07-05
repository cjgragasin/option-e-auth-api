import json
import boto3
import os
import uuid
from datetime import datetime
from botocore.exceptions import ClientError

# AWS clients
cognito = boto3.client("cognito-idp", region_name=os.environ["REGION"])
dynamodb = boto3.resource("dynamodb", region_name=os.environ["REGION"])
table = dynamodb.Table(os.environ["TABLE_NAME"])

CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]


# =============================================================
# HELPERS
# =============================================================

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }

def get_user_id(event):
    """Extract user ID from the validated JWT claims (injected by API Gateway)"""
    return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]


# =============================================================
# ROUTES
# =============================================================

def register(body):
    """POST /register — create a new Cognito user"""
    try:
        cognito.sign_up(
            ClientId=CLIENT_ID,
            Username=body["email"],
            Password=body["password"],
            UserAttributes=[{"Name": "email", "Value": body["email"]}]
        )
        # Auto-confirm user so login works immediately (no email verification needed for learning)
        cognito.admin_confirm_sign_up(
            UserPoolId=os.environ["USER_POOL_ID"],
            Username=body["email"]
        )
        return response(201, {"message": "User registered successfully"})
    except ClientError as e:
        return response(400, {"error": e.response["Error"]["Message"]})


def login(body):
    """POST /login — authenticate and return JWT tokens"""
    try:
        result = cognito.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={
                "USERNAME": body["email"],
                "PASSWORD": body["password"]
            },
            ClientId=CLIENT_ID
        )
        tokens = result["AuthenticationResult"]
        return response(200, {
            "access_token": tokens["AccessToken"],   # Use this in Authorization header
            "id_token": tokens["IdToken"],
            "expires_in": tokens["ExpiresIn"]
        })
    except ClientError as e:
        return response(401, {"error": e.response["Error"]["Message"]})


def get_notes(event):
    """GET /notes — fetch all notes for the logged-in user"""
    user_id = get_user_id(event)
    result = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("user_id").eq(user_id)
    )
    return response(200, {"notes": result["Items"]})


def create_note(event, body):
    """POST /notes — create a new note for the logged-in user"""
    user_id = get_user_id(event)
    note = {
        "user_id": user_id,
        "note_id": str(uuid.uuid4()),
        "content": body["content"],
        "created_at": datetime.utcnow().isoformat()
    }
    table.put_item(Item=note)
    return response(201, {"note": note})


# =============================================================
# MAIN HANDLER — routes requests to the right function
# =============================================================

def lambda_handler(event, context):
    method = event["requestContext"]["http"]["method"]
    path   = event["requestContext"]["http"]["path"]

# Fix single quotes to double quotes if PowerShell mangled it
    raw_body = event.get("body") or "{}"
    raw_body = raw_body.replace("'", '"')
    body = json.loads(raw_body)

    # Public routes (no auth needed)
    if path == "/register" and method == "POST":
        return register(body)
    if path == "/login" and method == "POST":
        return login(body)

    # Protected routes (API Gateway validates JWT before reaching here)
    if path == "/notes" and method == "GET":
        return get_notes(event)
    if path == "/notes" and method == "POST":
        return create_note(event, body)

    return response(404, {"error": "Route not found"})
