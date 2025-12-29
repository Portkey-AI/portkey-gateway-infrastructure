################################################################################
# File: terraform/additional-resources.tf
################################################################################


# Allow traffic to load balancer on prod port
resource "aws_vpc_security_group_ingress_rule" "lb_prod_listener_ingress" {
  count             = length(local.allowed_lb_cidrs)
  security_group_id = module.gateway.lb_security_group_id
  ip_protocol       = "tcp"
  from_port         = var.tls_certificate_arn != "" ? 443 : 80
  to_port           = var.tls_certificate_arn != "" ? 443 : 80
  cidr_ipv4         = local.allowed_lb_cidrs[count.index]
}

# Allow traffic to load balancer on test port
resource "aws_vpc_security_group_ingress_rule" "lb_test_listener_ingress" {
  count             = var.create_lb && var.enable_blue_green ? length(local.allowed_lb_cidrs) : 0
  security_group_id = module.gateway.lb_security_group_id
  ip_protocol       = "tcp"
  from_port         = var.tls_certificate_arn != "" ? 8443 : 8080
  to_port           = var.tls_certificate_arn != "" ? 8443 : 8080
  cidr_ipv4         = local.allowed_lb_cidrs[count.index]
}

# Allow traffic from load balancer
resource "aws_vpc_security_group_ingress_rule" "gateway_service_lb_ingress" {
  count                        = var.create_lb && (var.server_mode == "all" || var.server_mode == "gateway") ? 1 : 0
  security_group_id            = module.gateway.ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.gateway_config.gateway_port
  to_port                      = var.gateway_config.gateway_port
  referenced_security_group_id = module.gateway.lb_security_group_id
}

# Allow traffic from load balancer
resource "aws_vpc_security_group_ingress_rule" "mcp_service_lb_ingress" {
  count                        = var.create_lb && (var.server_mode == "all" || var.server_mode == "mcp") ? 1 : 0
  security_group_id            = module.gateway.ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.gateway_config.mcp_port
  to_port                      = var.gateway_config.mcp_port
  referenced_security_group_id = module.gateway.lb_security_group_id
}


# Allow traffic to data service from gateway
resource "aws_vpc_security_group_ingress_rule" "dataservice_from_gateway_ingress" {
  count                        = var.dataservice_config.enable_dataservice ? 1 : 0
  security_group_id            = module.data_service[0].ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
  referenced_security_group_id = module.gateway.ecs_service_security_group_id
  depends_on                   = [module.gateway.ecs_service_security_group_id]
}


# Allow traffic to gateway from data service
resource "aws_vpc_security_group_ingress_rule" "gateway_from_dataservice_ingress" {
  count                        = var.dataservice_config.enable_dataservice ? 1 : 0
  security_group_id            = module.gateway.ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.gateway_config.gateway_port
  to_port                      = var.gateway_config.gateway_port
  referenced_security_group_id = module.data_service[0].ecs_service_security_group_id
  depends_on                   = [module.data_service[0].ecs_service_security_group_id]
}

# Allow traffic to redis from gateway service
resource "aws_vpc_security_group_ingress_rule" "redis_lb_from_gateway_ingress" {
  count                        = var.redis_type == "redis" ? 1 : 0
  security_group_id            = module.redis[0].ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = module.gateway.ecs_service_security_group_id
  depends_on                   = [module.gateway.ecs_service_security_group_id]
}

# Allow traffic to redis from data service
resource "aws_vpc_security_group_ingress_rule" "redis_lb_from_dataservice_ingress" {
  count                        = var.redis_type == "redis" && var.dataservice_config.enable_dataservice ? 1 : 0
  security_group_id            = module.redis[0].ecs_service_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = module.data_service[0].ecs_service_security_group_id
  depends_on                   = [module.data_service[0].ecs_service_security_group_id]
}

# ============================================================================
# SERVICE DISCOVERY NAMESPACE FOR SERVICE CONNECT
# ============================================================================

resource "aws_service_discovery_http_namespace" "service_discovery_namespace" {
  name        = local.namespace
  description = "Service discovery namespace for Portkey Gateway"
  lifecycle {
    ignore_changes = [
      description
    ]
  }
}