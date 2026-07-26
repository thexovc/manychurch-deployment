terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend "s3" {
  #   bucket         = "manychurch-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "manychurch-terraform-locks"
  # }
}

provider "aws" {
  region  = var.aws_region
}

# module "prod_ecs" {
#   source             = "../../modules/ecs_ec2"
#   environment        = "prod"
#   aws_region         = var.aws_region
#   instance_type      = "t3.small"
#   ssh_public_key     = var.ssh_public_key
#   secrets_arn        = var.secrets_arn
#   vpc_cidr           = "10.1.0.0/16"
#   subnet_cidr        = "10.1.1.0/24"
#   nginx_image        = var.nginx_image
#   gateway_image      = var.gateway_image
#   auth_image         = var.auth_image
#   church_image       = var.church_image
#   member_image       = var.member_image
#   course_image       = var.course_image
#   giving_image       = var.giving_image
#   wallet_image       = var.wallet_image
#   notification_image = var.notification_image
#   support_image      = var.support_image
#   admin_image        = var.admin_image
# }

# output "ecs_cluster_name" {
#   value = module.prod_ecs.ecs_cluster_name
# }

# output "ecs_service_core_name" {
#   value = module.prod_ecs.ecs_service_core_name
# }

# output "ecs_service_name" {
#   value = module.prod_ecs.ecs_service_name
# }
