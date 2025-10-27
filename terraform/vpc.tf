################################################################################
# File: terraform/vpc.tf
################################################################################

module "vpc" {

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.0"
  count   = var.create_new_vpc ? 1 : 0
  name    = "${var.project_name}-vpc"
  cidr    = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets_cidrs
  public_subnets  = local.public_subnets_cidrs

  enable_nat_gateway = true

  single_nat_gateway = var.single_nat_gateway

  one_nat_gateway_per_az = !var.single_nat_gateway

  default_vpc_enable_dns_hostnames = true

  default_vpc_enable_dns_support = true

}

