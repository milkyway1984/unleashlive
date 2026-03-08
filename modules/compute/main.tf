terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  current_region = data.aws_region.current.name
}

# ════════════════════════════════════════════════════════════════════════════
# SECURITY GROUP
# ════════════════════════════════════════════════════════════════════════════

resource "aws_security_group" "ecs_task" {
  name        = "${var.prefix}-ecs-task-sg-${var.region}"
  description = "Security group for ECS Fargate tasks – outbound only"
  vpc_id      = var.vpc_id

  # Allow all outbound (needed to reach SNS endpoint and ECR)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name      = "${var.prefix}-ecs-task-sg-${var.region}"
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# DYNAMODB TABLE
# ════════════════════════════════════════════════════════════════════════════

resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${var.prefix}-GreetingLogs-${var.region}"
  # cost-optimised – no provisioned capacity
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Point-in-time recovery – good practice, no cost for small tables
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name      = "${var.prefix}-GreetingLogs-${var.region}"
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# IAM – LAMBDA EXECUTION ROLE
# ════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_exec" {
  name = "${var.prefix}-lambda-exec-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "${var.prefix}-lambda-policy-${var.region}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${local.account_id}:*"
      },
      # DynamoDB – scoped to this table only
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.greeting_logs.arn
      },
      # SNS publish – scoped to Unleash live topic only
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      },
      # ECS RunTask – scoped to this cluster's tasks
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks"
        ]
        Resource = [
          aws_ecs_task_definition.dispatcher.arn,
          aws_ecs_cluster.main.arn
        ]
      },
      # PassRole – allow Lambda to pass the ECS task role
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_exec.arn,
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

# ════════════════════════════════════════════════════════════════════════════
# IAM – ECS TASK EXECUTION ROLE (pull image, push logs)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "ecs_task_exec" {
  name = "${var.prefix}-ecs-exec-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ════════════════════════════════════════════════════════════════════════════
# IAM – ECS TASK ROLE (what the container can do at runtime)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-ecs-task-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "ecs_task_sns" {
  name = "${var.prefix}-ecs-sns-policy-${var.region}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = var.sns_topic_arn
    }]
  })
}

# ════════════════════════════════════════════════════════════════════════════
# ECS CLUSTER + TASK DEFINITION
# ════════════════════════════════════════════════════════════════════════════

resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster-${var.region}"

  setting {
    name  = "containerInsights"
    # cost-optimised for assessment
    value = "disabled"
  }

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.prefix}-dispatcher-${var.region}"
  retention_in_days = 7

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_ecs_task_definition" "dispatcher" {
  family                   = "${var.prefix}-dispatcher-${var.region}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # 0.25 vCPU – minimum, cost-optimised
  cpu    = "256"
  # 512 MB – minimum for Fargate
  memory = "512"

  execution_role_arn = aws_iam_role.ecs_task_exec.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "dispatcher"
      image     = "amazon/aws-cli"
      essential = true

      # Publish SNS message then exit
      command = [
        "sns", "publish",
        "--topic-arn", var.sns_topic_arn,
        "--region", "us-east-1",
        "--message", jsonencode({
          email  = var.candidate_email
          source = "ECS"
          region = var.region
          repo   = var.github_repo
        })
      ]

      environment = [
        { name = "AWS_DEFAULT_REGION", value = "us-east-1" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.prefix}-dispatcher-${var.region}"
          "awslogs-region"        = local.current_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# LAMBDA – GREETER
# ════════════════════════════════════════════════════════════════════════════

data "archive_file" "greeter" {
  type        = "zip"
  source_file = "${path.module}/lambdas/greeter.py"
  output_path = "${path.module}/lambdas/greeter.zip"
}

resource "aws_cloudwatch_log_group" "greeter" {
  name              = "/aws/lambda/${var.prefix}-greeter-${var.region}"
  retention_in_days = 7

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_lambda_function" "greeter" {
  function_name    = "${var.prefix}-greeter-${var.region}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "greeter.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.greeter.output_path
  source_code_hash = data.archive_file.greeter.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN     = var.sns_topic_arn
      CANDIDATE_EMAIL   = var.candidate_email
      GITHUB_REPO       = var.github_repo
      EXECUTING_REGION  = var.region
    }
  }

  depends_on = [aws_cloudwatch_log_group.greeter]

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# LAMBDA – DISPATCHER
# ════════════════════════════════════════════════════════════════════════════

data "archive_file" "dispatcher" {
  type        = "zip"
  source_file = "${path.module}/lambdas/dispatcher.py"
  output_path = "${path.module}/lambdas/dispatcher.zip"
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${var.prefix}-dispatcher-${var.region}"
  retention_in_days = 7

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

resource "aws_lambda_function" "dispatcher" {
  function_name    = "${var.prefix}-dispatcher-${var.region}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "dispatcher.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dispatcher.output_path
  source_code_hash = data.archive_file.dispatcher.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      ECS_CLUSTER_ARN   = aws_ecs_cluster.main.arn
      ECS_TASK_DEF_ARN  = aws_ecs_task_definition.dispatcher.arn
      SUBNET_ID         = var.public_subnet_ids[0]
      SECURITY_GROUP_ID = aws_security_group.ecs_task.id
      EXECUTING_REGION  = var.region
    }
  }

  depends_on = [aws_cloudwatch_log_group.dispatcher]

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# API GATEWAY (HTTP API)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.prefix}-api-${var.region}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# Cognito JWT Authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project   = "unleash-assessment"
    ManagedBy = "terraform"
  }
}

# Lambda integrations
resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /greet"
  target             = "integrations/${aws_apigatewayv2_integration.greeter.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /dispatch"
  target             = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "greeter" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/greet"
}

resource "aws_lambda_permission" "dispatcher" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/dispatch"
}
