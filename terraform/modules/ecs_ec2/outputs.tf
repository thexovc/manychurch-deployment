output "ecs_cluster_name" {
  description = "The name of the ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_core_name" {
  description = "The name of the Core ECS Service"
  value       = aws_ecs_service.proxy_gateway.name
}

output "ecs_service_aux_name" {
  description = "The name of the Auxiliary ECS Service"
  value       = aws_ecs_service.course_giving.name
}

output "ecs_service_name" {
  description = "The name of the Core ECS Service (legacy)"
  value       = aws_ecs_service.proxy_gateway.name
}

output "public_ip" {
  description = "The public Elastic IP of the ECS EC2 host"
  value       = aws_eip.host_eip.public_ip
}
