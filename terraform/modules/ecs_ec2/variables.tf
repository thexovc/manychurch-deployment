variable "environment" {
  description = "The deployment environment (e.g. dev, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC network IP range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet IP range"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 Host Instance Class"
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key" {
  description = "SSH Public Key for EC2 host login"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for network subnet"
  type        = string
  default     = "us-east-1a"
}

variable "secrets_arn" {
  description = "The ARN of the AWS Secrets Manager Secret containing all app configuration"
  type        = string
}

# Image URIs for all 15 services
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

variable "postgres_image" {
  type    = string
  default = "postgres:16-alpine"
}

variable "rabbitmq_image" {
  type    = string
  default = "rabbitmq:3-management-alpine"
}

variable "prometheus_image" {
  type    = string
  default = "prom/prometheus:latest"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:latest"
}
