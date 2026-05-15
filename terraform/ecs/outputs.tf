################################################################################
# File: terraform/outputs.tf
################################################################################

output "vpc_id" {
  description = "VPC ID of created vpc"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = local.private_subnet_ids
}

output "load_balancer_dns_name" {
  description = "DNS of the Gateway's Load Balancer"
  value       = module.gateway.lb_dns_name
}

output "gateway_task_role_arn" {
  description = "IAM task role ARN for the gateway ECS service"
  value       = module.gateway.task_role_arn
}

output "data_service_task_role_arn" {
  description = "IAM task role ARN for the data-service ECS service"
  value       = try(module.data_service[0].task_role_arn, null)
}

output "redis_task_role_arn" {
  description = "IAM task role ARN for the Redis ECS service"
  value       = try(module.redis[0].task_role_arn, null)
}