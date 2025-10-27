# ============================================================================
# FILE: modules/ecs-service/outputs.tf
# ============================================================================

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.service.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.service.id
}

output "ecs_service_security_group_id" {
  description = "Security Group ID of the Load Balancer"
  value       = aws_security_group.service_sg.id
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.task_definition.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the LB"
  value       = try(aws_lb.lb[0].dns_name, null)
}

output "load_balancer_arn" {
  description = "ARN of the Load Balancer"
  value       = try(aws_lb.lb[0].arn, null)
}

output "load_balancer_security_group_id" {
  description = "Security Group ID of the Load Balancer"
  value       = try(aws_security_group.lb_sg[0].id, null)
}

output "service_connect_enabled" {
  description = "Whether Service Connect is enabled"
  value       = local.service_connect_enabled
}