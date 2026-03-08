"""
Lambda 2 – Dispatcher
  - Triggered by POST /dispatch
  - Calls ECS RunTask to launch a Fargate task that publishes to SNS
  - Returns 200 with task ARN and executing region
"""
import json
import os
import boto3


ECS_CLUSTER_ARN   = os.environ["ECS_CLUSTER_ARN"]
ECS_TASK_DEF_ARN  = os.environ["ECS_TASK_DEF_ARN"]
SUBNET_ID         = os.environ["SUBNET_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]
EXECUTING_REGION  = os.environ["EXECUTING_REGION"]

ecs = boto3.client("ecs", region_name=EXECUTING_REGION)


def handler(event, context):
    # ── Launch Fargate task ───────────────────────────────────────────────────
    response = ecs.run_task(
        cluster        = ECS_CLUSTER_ARN,
        taskDefinition = ECS_TASK_DEF_ARN,
        launchType     = "FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets":         [SUBNET_ID],
                "securityGroups":  [SECURITY_GROUP_ID],
                "assignPublicIp":  "ENABLED",   # public subnet – no NAT needed
            }
        },
        # Override not needed; command baked into task definition
    )

    tasks = response.get("tasks", [])
    if not tasks:
        failures = response.get("failures", [])
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "error":    "ECS RunTask returned no tasks",
                "failures": failures,
                "region":   EXECUTING_REGION,
            }),
        }

    task_arn = tasks[0]["taskArn"]

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message":  f"ECS task dispatched from {EXECUTING_REGION}",
            "region":   EXECUTING_REGION,
            "task_arn": task_arn,
        }),
    }
