# extra_services.tf

# Giving
resource "aws_service_discovery_service" "giving" {
  name = "giving"
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

resource "aws_ecs_task_definition" "giving" {
  family                   = "manychurch-dev-giving"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "giving"
      image             = var.giving_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50055 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }]
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "giving" } }
    }
  ])
}

resource "aws_ecs_service" "giving" {
  name            = "manychurch-dev-giving"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.giving.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.giving.arn
    container_name = "giving"
    container_port = 50055
  }
}

# Wallet
resource "aws_service_discovery_service" "wallet" {
  name = "wallet"
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

resource "aws_ecs_task_definition" "wallet" {
  family                   = "manychurch-dev-wallet"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "wallet"
      image             = var.wallet_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50056 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }]
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "wallet" } }
    }
  ])
}

resource "aws_ecs_service" "wallet" {
  name            = "manychurch-dev-wallet"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.wallet.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.wallet.arn
    container_name = "wallet"
    container_port = 50056
  }
}

# Notification
resource "aws_service_discovery_service" "notification" {
  name = "notification"
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

resource "aws_ecs_task_definition" "notification" {
  family                   = "manychurch-dev-notification"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "notification"
      image             = var.notification_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50057 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }]
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "notification" } }
    }
  ])
}

resource "aws_ecs_service" "notification" {
  name            = "manychurch-dev-notification"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.notification.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.notification.arn
    container_name = "notification"
    container_port = 50057
  }
}

# Messaging
resource "aws_service_discovery_service" "messaging" {
  name = "messaging"
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

resource "aws_ecs_task_definition" "messaging" {
  family                   = "manychurch-dev-messaging"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "messaging"
      image             = var.messaging_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50058 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" },
        { name = "REDIS_URL", value = "redis://redis.manychurch.local:6379" },
        { name = "RABBITMQ_URL", value = "amqp://guest:guest@rabbitmq.manychurch.local:5672/" }
      ]
      secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }]
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "messaging" } }
    }
  ])
}

resource "aws_ecs_service" "messaging" {
  name            = "manychurch-dev-messaging"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.messaging.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.messaging.arn
    container_name = "messaging"
    container_port = 50058
  }
}

# Admin
resource "aws_service_discovery_service" "admin" {
  name = "admin"
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

resource "aws_ecs_task_definition" "admin" {
  family                   = "manychurch-dev-admin"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "admin"
      image             = var.admin_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 8089 }]
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
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "admin" } }
    }
  ])
}

resource "aws_ecs_service" "admin" {
  name            = "manychurch-dev-admin"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.admin.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.admin.arn
    container_name = "admin"
    container_port = 8089
  }
}

# Support
resource "aws_service_discovery_service" "support" {
  name = "support"
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

resource "aws_ecs_task_definition" "support" {
  family                   = "manychurch-dev-support"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name              = "support"
      image             = var.support_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 8088 }]
      environment = [
        { name = "DB_HOST", value = "postgres.manychurch.local" },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = "manychurch" },
        { name = "DB_USER", value = "postgres" }
      ]
      secrets = [{ name = "DB_PASSWORD", valueFrom = "${var.secrets_arn}:db_password::" }]
      logConfiguration = { logDriver = "awslogs", options = { "awslogs-group" = aws_cloudwatch_log_group.app_logs.name, "awslogs-region" = var.aws_region, "awslogs-stream-prefix" = "support" } }
    }
  ])
}

resource "aws_ecs_service" "support" {
  name            = "manychurch-dev-support"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.support.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.support.arn
    container_name = "support"
    container_port = 8088
  }
}
