################################################################################
# File: terraform/privatelink.tf
################################################################################

resource "aws_vpc_endpoint_service" "gateway_endpoint_service" {
  count                      = var.enable_privatelink ? 1 : 0
  acceptance_required        = true
  network_load_balancer_arns = [module.gateway.load_balancer_arn]
  allowed_principals         = var.allow_portkey_account ? ["arn:aws:iam::299329113195:root"] : null
}