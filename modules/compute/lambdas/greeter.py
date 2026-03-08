"""
Lambda 1 – Greeter
  - Writes a log record to DynamoDB
  - Publishes verification payload to Unleash live SNS topic
  - Returns 200 with the executing region
"""
import json
import os
import uuid
import boto3
from datetime import datetime, timezone


DYNAMODB_TABLE   = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN    = os.environ["SNS_TOPIC_ARN"]
CANDIDATE_EMAIL  = os.environ["CANDIDATE_EMAIL"]
GITHUB_REPO      = os.environ["GITHUB_REPO"]
EXECUTING_REGION = os.environ["EXECUTING_REGION"]

# Clients are initialised outside the handler for Lambda execution context reuse
dynamodb = boto3.resource("dynamodb", region_name=EXECUTING_REGION)
sns      = boto3.client("sns", region_name="us-east-1")  # SNS topic is in us-east-1


def handler(event, context):
    record_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    # ── 1. Write to DynamoDB ──────────────────────────────────────────────────
    table = dynamodb.Table(DYNAMODB_TABLE)
    table.put_item(Item={
        "id":        record_id,
        "timestamp": timestamp,
        "region":    EXECUTING_REGION,
        "source":    "greeter-lambda",
    })

    # ── 2. Publish to Unleash live SNS topic ──────────────────────────────────
    sns_payload = {
        "email":  CANDIDATE_EMAIL,
        "source": "Lambda",
        "region": EXECUTING_REGION,
        "repo":   GITHUB_REPO,
    }
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Message=json.dumps(sns_payload),
    )

    # ── 3. Return response ────────────────────────────────────────────────────
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": f"Hello from {EXECUTING_REGION}!",
            "region":  EXECUTING_REGION,
            "id":      record_id,
        }),
    }
