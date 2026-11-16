# Layer 10: network. VPC, subnets, internet access
locals {
  name = "weatherapp"
  azs  = ["${var.region}a", "${var.region}b"] # EKS and ALB need 2 AZs, even without HA
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # cidrsubnet() carves /24s out of the /16 so we never hand-write overlapping ranges.
  public_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 1)]  # 10.0.1.0/24, 10.0.2.0/24
  private_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 11)] # 10.0.11.0/24, ...
  database_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 21)] # 10.0.21.0/24, ...

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = true # one NAT instead of one per AZ: no HA, 2/3 cheaper

  create_database_subnet_group = true # used next week by RDS

  enable_dns_hostnames = true # required by EKS
  enable_dns_support   = true

  # Tell the AWS Load Balancer Controller which subnets to use.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
