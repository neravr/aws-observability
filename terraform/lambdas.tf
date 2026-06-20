# App service Lambda
resource "aws_lambda_function" "app_service" {
  function_name = "app-service-${var.env}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  s3_bucket = data.aws_s3_bucket.lambda_packages.bucket
  s3_key    = "app-service.zip"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ENV        = var.env
      APP_REGION = var.region
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.app_service
  ]

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}

# Order service Lambda
resource "aws_lambda_function" "order_service" {
  function_name = "order-service-${var.env}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  s3_bucket = data.aws_s3_bucket.lambda_packages.bucket
  s3_key    = "order-service.zip"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ENV        = var.env
      APP_REGION = var.region
      ERROR_RATE = "0.3"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.order_service
  ]

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}

# Runbook generator Lambda
resource "aws_lambda_function" "runbook_generator" {
  function_name = "runbook-generator-${var.env}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  s3_bucket = data.aws_s3_bucket.lambda_packages.bucket
  s3_key    = "runbook-generator.zip"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ENV              = var.env
      APP_REGION       = var.region
      SNS_TOPIC_ARN    = aws_sns_topic.runbook_notifications.arn
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.runbook_generator
  ]

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}

# Allow CloudWatch alarm to trigger runbook generator via SNS
resource "aws_sns_topic_subscription" "runbook_lambda" {
  topic_arn = aws_sns_topic.runbook_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.runbook_generator.arn
}

resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.runbook_generator.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.runbook_notifications.arn
}