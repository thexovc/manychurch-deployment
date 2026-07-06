variable "aws_region" {
  description = "AWS region for Prod environment"
  type        = string
  default     = "us-east-1"
}

variable "ssh_public_key" {
  description = "Public SSH key for EC2 host"
  type        = string
}

variable "secrets_arn" {
  description = "ARN of AWS Secrets Manager secret holding configuration parameters"
  type        = string
}

# Image URIs for Prod microservices
variable "nginx_image" { type = string }
variable "gateway_image" { type = string }
variable "auth_image" { type = string }
variable "church_image" { type = string }
variable "member_image" { type = string }
variable "course_image" { type = string }
variable "giving_image" { type = string }
variable "wallet_image" { type = string }
variable "notification_image" { type = string }
variable "support_image" { type = string }
variable "admin_image" { type = string }
