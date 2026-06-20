output "sns_topic_arn" {
  value = aws_sns_topic.runbook_notifications.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "lambda_bucket" {
  value = aws_s3_bucket.lambda_packages.bucket
}

output "cloudwatch_alarm" {
  value = aws_cloudwatch_metric_alarm.error_rate.alarm_name
}