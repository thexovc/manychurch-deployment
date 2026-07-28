# dependencies.tf

# --- Redis Service ---
resource "aws_service_discovery_service" "redis" {
  name = "redis"
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

resource "aws_ecs_task_definition" "redis" {
  family                   = "manychurch-dev-redis"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "redis"
      image             = "redis:7-alpine"
      cpu               = 100
      memoryReservation = 128
      essential         = true
      portMappings      = [{ containerPort = 6379 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "redis"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "redis" {
  name            = "manychurch-dev-redis"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.redis.arn
    container_name = "redis"
    container_port = 6379
  }
}

# --- RabbitMQ Service ---
resource "aws_service_discovery_service" "rabbitmq" {
  name = "rabbitmq"
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

resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "manychurch-dev-rabbitmq"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "rabbitmq"
      image             = "rabbitmq:3-management-alpine"
      cpu               = 200
      memoryReservation = 256
      essential         = true
      portMappings      = [
        { containerPort = 5672 },
        { containerPort = 15672 }
      ]
      environment = [
        { name = "RABBITMQ_DEFAULT_USER", value = "guest" },
        { name = "RABBITMQ_DEFAULT_PASS", value = "guest" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "rabbitmq"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "manychurch-dev-rabbitmq"
  cluster         = module.compute.ecs_cluster_id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  service_registries {
    registry_arn   = aws_service_discovery_service.rabbitmq.arn
    container_name = "rabbitmq"
    container_port = 5672
  }
}
