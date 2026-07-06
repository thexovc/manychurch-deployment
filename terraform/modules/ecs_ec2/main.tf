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
  key_name   = "manychurch-${var.environment}-key"
  public_key = var.ssh_public_key
}

# EC2 Instance serving as our ECS Host Node
resource "aws_instance" "ecs_host" {
  ami                    = data.aws_ami.ecs.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ecs_host.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance_profile.name

  root_block_device {
    volume_size           = 30 # GP3 30GB standard size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh", {
    cluster_name = aws_ecs_cluster.main.name
  })

  tags = {
    Name        = "manychurch-${var.environment}-ecs-host"
    Environment = var.environment
  }
}

# Elastic IP allocation for host
resource "aws_eip" "host_eip" {
  domain = "vpc"
}

resource "aws_eip_association" "host_eip_assoc" {
  instance_id   = aws_instance.ecs_host.id
  allocation_id = aws_eip.host_eip.id
}

# CloudWatch Logs Group for Application Containers
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/manychurch-${var.environment}"
  retention_in_days = 7
}

# --- Consolidated ECS Task Definition (All 15 Containers) ---
# Mode is set to "host" so all containers share local interfaces and communicate via localhost.

resource "aws_ecs_task_definition" "app" {
  family                   = "manychurch-${var.environment}-app"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    # 1. Nginx Reverse Proxy
    {
      name      = "nginx"
      image     = var.nginx_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [
        {
          containerPort = 80
        },
        {
          containerPort = 443
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },

    # 2. Gateway API Service
    {
      name      = "gateway"
      image     = var.gateway_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [
        {
          containerPort = 8080
        }
      ]
      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AUTH_SERVICE_ADDR", value = "127.0.0.1:50051" },
        { name = "CHURCH_SERVICE_ADDR", value = "127.0.0.1:50052" },
        { name = "MEMBER_SERVICE_ADDR", value = "127.0.0.1:50053" },
        { name = "NOTIFICATION_SERVICE_ADDR", value = "127.0.0.1:50054" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "gateway"
        }
      }
    },

    # 3. PostgreSQL Database
    {
      name      = "postgres"
      image     = var.postgres_image
      cpu       = 200
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 5432
        }
      ]
      environment = [
        { name = "POSTGRES_DB", value = "manychurch" },
        { name = "POSTGRES_USER", value = "postgres" }
      ]
      secrets = [
        {
          name      = "POSTGRES_PASSWORD"
          valueFrom = "${var.secrets_arn}:db_password::"
        }
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "postgres"
        }
      }
    },

    # 4. RabbitMQ Message Broker
    {
      name      = "rabbitmq"
      image     = var.rabbitmq_image
      cpu       = 150
      memory    = 192
      essential = true
      portMappings = [
        {
          containerPort = 5672
        },
        {
          containerPort = 15672
        }
      ]
      environment = [
        { name = "RABBITMQ_DEFAULT_USER", value = "manychurch_admin" }
      ]
      secrets = [
        {
          name      = "RABBITMQ_DEFAULT_PASS"
          valueFrom = "${var.secrets_arn}:rabbitmq_password::"
        }
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "rabbitmq"
        }
      }
    },

    # 5. Auth Service
    {
      name      = "auth"
      image     = var.auth_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [{ containerPort = 50051 }]
      environment = [
        { name = "DB_HOST", value = "127.0.0.1" },
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "auth"
        }
      }
    },

    # 6. Church Service
    {
      name      = "church"
      image     = var.church_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [{ containerPort = 50052 }]
      environment = [
        { name = "DB_HOST", value = "127.0.0.1" },
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "church"
        }
      }
    },

    # 7. Member Service
    {
      name      = "member"
      image     = var.member_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [{ containerPort = 50053 }]
      environment = [
        { name = "DB_HOST", value = "127.0.0.1" },
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "member"
        }
      }
    },

    # 8. Notification Service
    {
      name      = "notification"
      image     = var.notification_image
      cpu       = 100
      memory    = 64
      essential = true
      portMappings = [{ containerPort = 50054 }]
      environment = [
        { name = "RABBITMQ_URL", value = "amqp://manychurch_admin:localhost:5672/" }
      ]
      secrets = [
        { name = "RABBITMQ_PASSWORD", valueFrom = "${var.secrets_arn}:rabbitmq_password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "notification"
        }
      }
    },

    # 9. Course Service
    {
      name      = "course"
      image     = var.course_image
      cpu       = 50
      memory    = 48
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "course"
        }
      }
    },

    # 10. Giving Service
    {
      name      = "giving"
      image     = var.giving_image
      cpu       = 50
      memory    = 48
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "giving"
        }
      }
    },

    # 11. Wallet Service
    {
      name      = "wallet"
      image     = var.wallet_image
      cpu       = 50
      memory    = 48
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "wallet"
        }
      }
    },

    # 12. Support Service
    {
      name      = "support"
      image     = var.support_image
      cpu       = 50
      memory    = 48
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "support"
        }
      }
    },

    # 13. Admin Service
    {
      name      = "admin"
      image     = var.admin_image
      cpu       = 50
      memory    = 48
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "admin"
        }
      }
    },

    # 14. Prometheus Monitoring
    {
      name      = "prometheus"
      image     = var.prometheus_image
      cpu       = 100
      memory    = 96
      essential = true
      portMappings = [{ containerPort = 9090 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    },

    # 15. Grafana Analytics
    {
      name      = "grafana"
      image     = var.grafana_image
      cpu       = 100
      memory    = 96
      essential = true
      portMappings = [{ containerPort = 3000 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  # Persistent Volume configurations
  volume {
    name      = "postgres_data"
    host_path = "/var/lib/manychurch/postgres_data"
  }

  volume {
    name      = "rabbitmq_data"
    host_path = "/var/lib/manychurch/rabbitmq_data"
  }
}

# --- ECS Service Definition ---

resource "aws_ecs_service" "app" {
  name            = "manychurch-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"
}
