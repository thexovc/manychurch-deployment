# Query the official AWS ECS-Optimized Amazon Linux 2 AMI
data "aws_ami" "ecs" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

# --- VPC & Networking Setup ---

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "manychurch-${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "manychurch-${var.environment}-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name        = "manychurch-${var.environment}-public-subnet"
    Environment = var.environment
  }
}

# Route Table for Internet Access
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "manychurch-${var.environment}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---

resource "aws_security_group" "ecs_host" {
  name        = "manychurch-${var.environment}-ecs-host-sg"
  description = "Security group for ECS Host EC2 instance"
  vpc_id      = aws_vpc.main.id

  # Inbound HTTP / HTTPS (Routed to Nginx container)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "manychurch-${var.environment}-ecs-host-sg"
    Environment = var.environment
  }
}

# --- IAM Roles & Profiles ---

# EC2 Instance Profile (Allows EC2 to join ECS Cluster)
resource "aws_iam_role" "ecs_instance_role" {
  name = "manychurch-${var.environment}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "manychurch-${var.environment}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# ECS Task Execution Role (Allows ECS to pull ECR images and fetch Secrets Manager secrets)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "manychurch-${var.environment}-task-execution-role"

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

# Grant execution role access to Secrets Manager Configuration
resource "aws_iam_policy" "ecs_secrets_policy" {
  name        = "manychurch-${var.environment}-ecs-secrets-policy"
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

# ECS Task Role (Allows container code to access AWS services if needed)
resource "aws_iam_role" "ecs_task_role" {
  name = "manychurch-${var.environment}-task-role"

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

# --- ECS Cluster & Host Instance ---

resource "aws_ecs_cluster" "main" {
  name = "manychurch-${var.environment}-cluster"
}

resource "aws_key_pair" "deployer" {
  key_name_prefix = "manychurch-${var.environment}-key-"
  public_key      = var.ssh_public_key
}

# EC2 Instances serving as our ECS Host Nodes (scaled to 8 instances for t3.micro cost optimization)
# ECS Capacity Provider and Auto Scaling Group
resource "aws_launch_template" "ecs_host" {
  name_prefix   = "manychurch-${var.environment}-ecs-host-"
  image_id      = data.aws_ami.ecs.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_host.id]
    subnet_id                   = aws_subnet.public.id
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    cluster_name  = aws_ecs_cluster.main.name
    instance_role = "worker"
    host_index    = 0
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                  = "manychurch-${var.environment}-ecs-asg"
  vpc_zone_identifier   = [aws_subnet.public.id]
  min_size              = 4
  max_size              = 4
  desired_capacity      = 4
  protect_from_scale_in = false

  launch_template {
    id      = aws_launch_template.ecs_host.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "manychurch-${var.environment}-ecs-host"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "ecs_cp" {
  name = "manychurch-${var.environment}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status          = "ENABLED"
      target_capacity = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs_ccp" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_cp.name]
}


# CloudWatch Logs Group for Application Containers
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/manychurch-${var.environment}"
  retention_in_days = 7
}

# --- Service Discovery ---
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "manychurch.local"
  description = "manychurch.local Service Discovery Namespace"
  vpc         = aws_vpc.main.id
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

resource "aws_service_discovery_service" "church" {
  name = "church"
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

resource "aws_service_discovery_service" "member" {
  name = "member"
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

# --- 1. Proxy & Gateway Service Task Definition ---
resource "aws_ecs_task_definition" "proxy_gateway" {
  family                   = "manychurch-${var.environment}-proxy-gateway"
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
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AUTH_SERVICE_ADDR", value = "auth.manychurch.local:50051" },
        { name = "CHURCH_SERVICE_ADDR", value = "church.manychurch.local:50052" },
        { name = "MEMBER_SERVICE_ADDR", value = "member.manychurch.local:50053" },
        { name = "NOTIFICATION_SERVICE_ADDR", value = "notification.manychurch.local:50054" }
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

# --- 2. Postgres Service Task Definition ---
resource "aws_ecs_task_definition" "postgres" {
  family                   = "manychurch-${var.environment}-postgres"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "postgres"
      image             = var.postgres_image
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

# --- 3. RabbitMQ & Notification Service Task Definition ---
resource "aws_ecs_task_definition" "rabbitmq_notification" {
  family                   = "manychurch-${var.environment}-rabbitmq-notification"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "rabbitmq"
      image             = var.rabbitmq_image
      cpu               = 150
      memoryReservation = 192
      essential         = true
      portMappings = [
        { containerPort = 5672 },
        { containerPort = 15672 }
      ]
      environment = [
        { name = "RABBITMQ_DEFAULT_USER", value = "manychurch_admin" }
      ]
      secrets = [
        { name = "RABBITMQ_DEFAULT_PASS", valueFrom = "${var.secrets_arn}:rabbitmq_password::" }
      ]
      mountPoints = [
        {
          containerPath = "/var/lib/rabbitmq"
          sourceVolume  = "rabbitmq_data"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "rabbitmq"
        }
      }
    },
    {
      name              = "notification"
      image             = var.notification_image
      cpu               = 100
      memoryReservation = 64
      essential         = true
      portMappings      = [{ containerPort = 50054 }]
      environment = [
        { name = "RABBITMQ_URL", value = "amqp://manychurch_admin:rabbitmq.manychurch.local:5672/" }
      ]
      secrets = [
        { name = "RABBITMQ_PASSWORD", valueFrom = "${var.secrets_arn}:rabbitmq_password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "notification"
        }
      }
    }
  ])

  volume {
    name      = "rabbitmq_data"
    host_path = "/var/lib/manychurch/rabbitmq_data"
  }
}

# --- 4. Auth, Church & Member Service Task Definition ---
resource "aws_ecs_task_definition" "auth_church_member" {
  family                   = "manychurch-${var.environment}-auth-church-member"
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

# --- 5. Course & Giving Service Task Definition ---
resource "aws_ecs_task_definition" "course_giving" {
  family                   = "manychurch-${var.environment}-course-giving"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "course"
      image             = var.course_image
      cpu               = 100
      memoryReservation = 256
      essential         = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "course"
        }
      }
    },
    {
      name              = "giving"
      image             = var.giving_image
      cpu               = 100
      memoryReservation = 256
      essential         = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "giving"
        }
      }
    }
  ])
}

# --- 6. Wallet & Support Service Task Definition ---
resource "aws_ecs_task_definition" "wallet_support" {
  family                   = "manychurch-${var.environment}-wallet-support"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "wallet"
      image             = var.wallet_image
      cpu               = 100
      memoryReservation = 256
      essential         = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "wallet"
        }
      }
    },
    {
      name              = "support"
      image             = var.support_image
      cpu               = 100
      memoryReservation = 256
      essential         = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "support"
        }
      }
    }
  ])
}

# --- 7. Admin & Prometheus Service Task Definition ---
resource "aws_ecs_task_definition" "admin_prometheus" {
  family                   = "manychurch-${var.environment}-admin-prometheus"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "admin"
      image             = var.admin_image
      cpu               = 100
      memoryReservation = 256
      essential         = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "admin"
        }
      }
    },
    {
      name              = "prometheus"
      image             = var.prometheus_image
      cpu               = 200
      memoryReservation = 512
      essential         = true
      portMappings      = [{ containerPort = 9090 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    }
  ])
}

# --- 8. Grafana Service Task Definition ---
resource "aws_ecs_task_definition" "grafana" {
  family                   = "manychurch-${var.environment}-grafana"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name              = "grafana"
      image             = var.grafana_image
      cpu               = 200
      memoryReservation = 512
      essential         = true
      portMappings      = [{ containerPort = 3000 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])
}

# --- ECS Service Definitions ---

resource "aws_ecs_service" "proxy_gateway" {
  name            = "manychurch-proxy-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.proxy_gateway.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:role == proxy"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
}

resource "aws_ecs_service" "postgres" {
  name            = "manychurch-postgres"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 1"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.postgres.arn
    container_name = "postgres"
    container_port = 5432
  }
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "manychurch-rabbitmq"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq_notification.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 2"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.rabbitmq.arn
    container_name = "rabbitmq"
    container_port = 5672
  }
}

resource "aws_ecs_service" "auth" {
  name            = "manychurch-auth"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth_church_member.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 3"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.auth.arn
    container_name = "auth"
    container_port = 50051
  }
}

resource "aws_ecs_service" "church" {
  name            = "manychurch-church"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth_church_member.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 3"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.church.arn
    container_name = "church"
    container_port = 50052
  }
}

resource "aws_ecs_service" "member" {
  name            = "manychurch-member"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth_church_member.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 3"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.member.arn
    container_name = "member"
    container_port = 50053
  }
}

resource "aws_ecs_service" "notification" {
  name            = "manychurch-notification"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq_notification.arn
  desired_count   = 1
  # (Note: we run rabbitmq on host 2, and notification service replica on host 4)
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 4"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.notification.arn
    container_name = "notification"
    container_port = 50054
  }
}

resource "aws_ecs_service" "course_giving" {
  name            = "manychurch-course-giving"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.course_giving.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 5"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
}

resource "aws_ecs_service" "wallet_support" {
  name            = "manychurch-wallet-support"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wallet_support.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 6"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
}

resource "aws_ecs_service" "admin_prometheus" {
  name            = "manychurch-admin-prometheus"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.admin_prometheus.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 7"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
}

resource "aws_ecs_service" "grafana" {
  name            = "manychurch-grafana"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:host_index == 7"
  }
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
}
