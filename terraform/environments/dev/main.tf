terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "manychurch-terraform-state-dev-af1"
    key    = "dev/terraform.tfstate"
    region = "af-south-1"
  }
}

provider "aws" {
  region  = var.aws_region
}

module "networking" {
  source = "../../modules/networking"

  environment                = "dev"
  vpc_cidr_block             = "10.0.0.0/16"
  public_subnet_cidr_blocks  = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones         = ["af-south-1a", "af-south-1b"]
  
  resource_tags = {
    Project     = "ManyChurch"
    Environment = "dev"
  }
}

module "compute" {
  source = "../../modules/compute"

  environment = "dev"
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.public_subnet_ids
  
  instance_type = "t3.small"
  min_size      = 1
  max_size      = 1
  desired_capacity = 1

  resource_tags = {
    Project     = "ManyChurch"
    Environment = "dev"
  }
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}

# --- IAM Roles for ECS Tasks ---
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "manychurch-dev-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_secrets_policy" {
  name        = "manychurch-dev-ecs-secrets-policy"
  description = "Allows Task Execution Role to read Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.secrets_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_secrets_policy.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name = "manychurch-dev-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# --- CloudWatch Logs ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/manychurch-dev"
  retention_in_days = 7
}

# --- Service Discovery ---
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "manychurch.local"
  description = "manychurch.local Service Discovery Namespace"
  vpc         = module.networking.vpc_id
}

resource "aws_service_discovery_service" "postgres" {
  name = "postgres"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "auth" {
  name = "auth"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "SRV"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

# --- Task Definitions ---
# Total CPU: 200, Total Memory: 128
resource "aws_ecs_task_definition" "proxy_gateway" {
  family                   = "manychurch-dev-proxy-gateway"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "nginx"
      image             = var.nginx_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings = [
        { containerPort = 80 },
        { containerPort = 443 }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },
    {
      name              = "gateway"
      image             = var.gateway_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings = [
        { containerPort = 8080 }
      ]
      environment = [
        { name = "ENVIRONMENT", value = "dev" },
        { name = "AUTH_SERVICE_ADDR", value = "auth.manychurch.local:50051" },
        { name = "CHURCH_SERVICE_ADDR", value = "auth.manychurch.local:50052" },
        { name = "MEMBER_SERVICE_ADDR", value = "auth.manychurch.local:50053" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "gateway"
        }
      }
    }
  ])
}

# Total CPU: 200, Total Memory: 256
resource "aws_ecs_task_definition" "postgres" {
  family                   = "manychurch-dev-postgres"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "postgres"
      image             = "postgres:15-alpine" # Assuming standard image or from var
      cpu               = 200
      memoryReservation = 256
      essential         = true
      portMappings = [
        { containerPort = 5432 }
      ]
      environment = [
        { name = "POSTGRES_DB", value = "manychurch" },
        { name = "POSTGRES_USER", value = "postgres" }
      ]
      secrets = [
        { name = "POSTGRES_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }
      ]
      mountPoints = [
        {
          containerPath = "/var/lib/postgresql/data"
          sourceVolume  = "postgres_data"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "postgres"
        }
      }
    }
  ])

  volume {
    name      = "postgres_data"
    host_path = "/var/lib/manychurch/postgres_data"
  }
}

# Total CPU: 300, Total Memory: 192
resource "aws_ecs_task_definition" "auth_church_member" {
  family                   = "manychurch-dev-auth-church-member"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "auth"
      image             = var.auth_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50051 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" },
        { name = "JWT_SECRET", valueFrom = "${var.secrets_arn}:jwt_secret::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "auth"
        }
      }
    },
    {
      name              = "church"
      image             = var.church_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50052 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "church"
        }
      }
    },
    {
      name              = "member"
      image             = var.member_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50053 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "member"
        }
      }
    }
  ])
}

# --- ECS Services ---
resource "aws_ecs_service" "proxy_gateway" {
  name            = "manychurch-dev-proxy-gateway"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.proxy_gateway.arn
  desired_count   = 1
}

resource "aws_ecs_service" "postgres" {
  name            = "manychurch-dev-postgres"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.postgres.arn
    container_name = "postgres"
    container_port = 5432
  }
}

resource "aws_ecs_service" "auth" {
  name            = "manychurch-dev-auth"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.auth_church_member.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.auth.arn
    container_name = "auth"
    container_port = 50051
  }
}
