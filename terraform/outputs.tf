################################################################################
# File: terraform/outputs.tf
################################################################################

output "vpc_id" {
  description = "VPC ID of created vpc"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subents"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of public subents"
  value       = local.private_subnet_ids
}

output "load_balancer_dns_name" {
  description = "DNS of the Gateway's Network Load Balancer"
  value       = module.gateway.load_balancer_dns_name
}