# ============================================================================
# FILE: modules/ecs-service/security-group.tf
# ============================================================================

# Security Group for Load Balancer
resource "aws_security_group" "lb_sg" {
  count       = local.create_lb ? 1 : 0
  name_prefix = "${local.service_name}-lb-sg-${random_id.suffix.hex}"
  description = "Security group for data service ALB"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.service_name}-lb-sg-${random_id.suffix.hex}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Load Balancer Egress Rule - Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "lb_egress" {
  count             = local.create_lb ? 1 : 0
  security_group_id = aws_security_group.lb_sg[0].id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Security Group for ECS Service
resource "aws_security_group" "service_sg" {
  name_prefix = "${local.service_name}-sg-${random_id.suffix.hex}"
  description = "Security group for data service"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.service_name}-sg-${random_id.suffix.hex}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Service Egress Rule - Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "service_egress" {
  security_group_id = aws_security_group.service_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}