import re

with open("main.tf", "r") as f:
    content = f.read()

# 1. Replace aws_instance and EIP with ASG and Launch Template
instance_regex = re.compile(r'resource "aws_instance" "ecs_host" \{.*?\n\}\n', re.DOTALL)
eip_regex = re.compile(r'# Elastic IP allocation.*?resource "aws_eip_association" "host_eip_assoc" \{.*?\n\}\n', re.DOTALL)

replacement = """# ECS Capacity Provider and Auto Scaling Group
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
  cluster_name = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.ecs_cp.name]
}
"""

content = instance_regex.sub(replacement, content)
content = eip_regex.sub('', content)

# 2. Update awslogs-region
content = content.replace('"awslogs-region"        = "us-east-1"', '"awslogs-region"        = var.aws_region')

# 3. Replace static Route 53 records with Service Discovery
r53_regex = re.compile(r'# --- Route 53 Private Hosted Zone & Records for DNS-based Service Discovery ---.*?# --- 1. Proxy & Gateway Service Task Definition ---', re.DOTALL)

sd_replacement = """# --- Service Discovery ---
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
      type = "A"
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
      type = "A"
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
      type = "A"
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
      type = "A"
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
      type = "A"
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
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

# --- 1. Proxy & Gateway Service Task Definition ---"""

content = r53_regex.sub(sd_replacement, content)

# 4. Modify aws_ecs_service block to use capacity_providers instead of launch_type
# and add service_registry blocks

def replace_ecs_service(match):
    name = match.group(1)
    svc_name = match.group(2)
    rest = match.group(3)
    
    # Remove launch_type and placement_constraints
    rest = re.sub(r'\s*launch_type\s*=\s*"EC2"\n', '\n', rest)
    rest = re.sub(r'\s*# Pin.*?\n', '\n', rest)
    rest = re.sub(r'\s*placement_constraints\s*\{.*?\n\s*\}\n', '\n', rest, flags=re.DOTALL)
    
    cp_strategy = """  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ecs_cp.name
    weight            = 100
  }
"""
    
    registry = ""
    # Map the service names to the SD registries
    if name == "postgres":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.postgres.arn
  }
"""
    elif name == "rabbitmq":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.rabbitmq.arn
  }
"""
    elif name == "auth":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.auth.arn
  }
"""
    elif name == "church":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.church.arn
  }
"""
    elif name == "member":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.member.arn
  }
"""
    elif name == "notification":
        registry = """  service_registries {
    registry_arn = aws_service_discovery_service.notification.arn
  }
"""

    return f'resource "aws_ecs_service" "{name}" {{\n  name            = "{svc_name}"\n{rest}\n{cp_strategy}{registry}}}'

service_regex = re.compile(r'resource "aws_ecs_service" "(\w+)" \{\n\s*name\s*=\s*"([^"]+)"\n(.*?)\n\}', re.DOTALL)
content = service_regex.sub(replace_ecs_service, content)

with open("main.tf", "w") as f:
    f.write(content)

