terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "aws-observability-tfstate-138094353623"
    key    = "terraform/state"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

# S3 bucket for Lambda deployment packages
resource "aws_s3_bucket" "lambda_packages" {
  bucket        = "aws-observability-lambda-${var.account_id}"
  force_destroy = true

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}

# X-Ray sampling rule
resource "aws_xray_sampling_rule" "observability" {
  rule_name      = "observability-sampling"
  priority       = 1000
  reservoir_size = 5
  fixed_rate     = 1.0
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"
  version        = 1
}

# SNS topic for runbook notifications
resource "aws_sns_topic" "runbook_notifications" {
  name = "runbook-notifications-${var.env}"

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}

# SNS email subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.runbook_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "observability-lambda-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "observability-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:BatchGetTraces",
          "xray:GetTraceSummaries",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:DescribeAlarms",
          "bedrock:InvokeModel",
          "sns:Publish",
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "app_service" {
  name              = "/aws/lambda/app-service-${var.env}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "order_service" {
  name              = "/aws/lambda/order-service-${var.env}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "runbook_generator" {
  name              = "/aws/lambda/runbook-generator-${var.env}"
  retention_in_days = 7
}

# CloudWatch alarm — triggers runbook generator when error rate spikes
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "high-error-rate-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 2
  alarm_description   = "Lambda error rate exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = "order-service-${var.env}"
  }

  alarm_actions = [aws_sns_topic.runbook_notifications.arn]

  tags = {
    project    = "aws-observability"
    managed-by = "terraform"
  }
}