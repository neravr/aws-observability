variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
  default     = "138094353623"
}

variable "sns_email" {
  type        = string
  description = "Email address for runbook notifications"
}

variable "bedrock_model_id" {
  type        = string
  description = "AWS Bedrock model ID"
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}