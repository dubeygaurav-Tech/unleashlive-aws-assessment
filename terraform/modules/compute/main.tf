##############################################################
# Module: compute
# Creates: VPC, API Gateway, Lambda x2, DynamoDB, ECS Fargate
# Deployed identically to EACH region via multi-provider setup
##############################################################

#--------------------------------------------------------------
# VPC – minimal public-subnet setup (avoids NAT GW cost)
#--------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.project}-vpc-${var.aws_region}" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.project}-igw-${var.aws_region}" })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.project}-public-${count.index}-${var.aws_region}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "${var.project}-rt-public-${var.aws_region}" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

#--------------------------------------------------------------
# Security Groups
#--------------------------------------------------------------
resource "aws_security_group" "fargate_task" {
  name        = "${var.project}-fargate-sg-${var.aws_region}"
  description = "Outbound-only for Fargate tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-fargate-sg-${var.aws_region}" })
}

#--------------------------------------------------------------
# DynamoDB – regional table
#--------------------------------------------------------------
resource "aws_dynamodb_table" "greeting_logs" {
  name         = "${var.project}-GreetingLogs-${var.aws_region}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

#--------------------------------------------------------------
# IAM – Lambda execution role
#--------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project}-lambda-exec-${var.aws_region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # DynamoDB
  statement {
    sid    = "DynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
    ]
    resources = [aws_dynamodb_table.greeting_logs.arn]
  }

  # SNS – cross-region publish to the Candidate Verification Topic
  statement {
    sid       = "SNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.candidate_sns_topic_arn]
  }

  # ECS RunTask (Dispatcher Lambda)
  statement {
    sid    = "ECSRunTask"
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "iam:PassRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.project}-lambda-policy-${var.aws_region}"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#--------------------------------------------------------------
# Lambda packaging
#--------------------------------------------------------------
data "archive_file" "greeter" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/greeter"
  output_path = "${path.module}/builds/greeter-${var.aws_region}.zip"
}

data "archive_file" "dispatcher" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/dispatcher"
  output_path = "${path.module}/builds/dispatcher-${var.aws_region}.zip"
}

#--------------------------------------------------------------
# Lambda 1 – Greeter
#--------------------------------------------------------------
resource "aws_lambda_function" "greeter" {
  function_name    = "${var.project}-greeter-${var.aws_region}"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.greeter.output_path
  source_code_hash = data.archive_file.greeter.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN        = var.candidate_sns_topic_arn
      CANDIDATE_EMAIL      = var.candidate_email
      GITHUB_REPO          = var.github_repo
      AWS_EXECUTING_REGION = var.aws_region
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "greeter" {
  name              = "/aws/lambda/${aws_lambda_function.greeter.function_name}"
  retention_in_days = 7
  tags              = var.tags
}

#--------------------------------------------------------------
# Lambda 2 – Dispatcher
#--------------------------------------------------------------
resource "aws_lambda_function" "dispatcher" {
  function_name    = "${var.project}-dispatcher-${var.aws_region}"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.dispatcher.output_path
  source_code_hash = data.archive_file.dispatcher.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ECS_CLUSTER_ARN        = aws_ecs_cluster.main.arn
      TASK_DEFINITION_ARN    = aws_ecs_task_definition.publisher.arn
      SUBNET_IDS             = join(",", aws_subnet.public[*].id)
      SECURITY_GROUP_ID      = aws_security_group.fargate_task.id
      AWS_EXECUTING_REGION   = var.aws_region
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${aws_lambda_function.dispatcher.function_name}"
  retention_in_days = 7
  tags              = var.tags
}

#--------------------------------------------------------------
# API Gateway HTTP API
#--------------------------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api-${var.aws_region}"
  protocol_type = "HTTP"
  description   = "AWS Assessment API – ${var.aws_region}"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
  }

  tags = var.tags
}

# Cognito JWT Authorizer – references the us-east-1 User Pool
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

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      caller          = "$context.identity.caller"
      user            = "$context.identity.user"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      resourcePath    = "$context.resourcePath"
      status          = "$context.status"
      protocol        = "$context.protocol"
      responseLength  = "$context.responseLength"
    })
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.project}-${var.aws_region}"
  retention_in_days = 7
  tags              = var.tags
}

# Lambda permissions for API GW
resource "aws_lambda_permission" "greeter" {
  statement_id  = "AllowAPIGatewayGreeter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/greet"
}

resource "aws_lambda_permission" "dispatcher" {
  statement_id  = "AllowAPIGatewayDispatcher"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/dispatch"
}

#--------------------------------------------------------------
# ECS Cluster
#--------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster-${var.aws_region}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

#--------------------------------------------------------------
# IAM – ECS Task Role
#--------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project}-ecs-task-role-${var.aws_region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecs_task_policy" {
  statement {
    sid       = "SNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.candidate_sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = "${var.project}-ecs-task-policy-${var.aws_region}"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_policy.json
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.project}-ecs-exec-role-${var.aws_region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#--------------------------------------------------------------
# CloudWatch Log Group for ECS Task
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_task" {
  name              = "/ecs/${var.project}-publisher-${var.aws_region}"
  retention_in_days = 7
  tags              = var.tags
}

#--------------------------------------------------------------
# ECS Task Definition – SNS publisher using amazon/aws-cli
#--------------------------------------------------------------
resource "aws_ecs_task_definition" "publisher" {
  family                   = "${var.project}-publisher-${var.aws_region}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "sns-publisher"
      image = "amazon/aws-cli:latest"

      # The command publishes the required JSON payload to the SNS topic, then exits.
      command = [
        "sns", "publish",
        "--topic-arn", var.candidate_sns_topic_arn,
        "--region", "us-east-1",
        "--message",
        jsonencode({
          email  = var.candidate_email
          source = "ECS"
          region = var.aws_region
          repo   = var.github_repo
        })
      ]

      environment = [
        { name = "AWS_DEFAULT_REGION", value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_task.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = var.tags
}
