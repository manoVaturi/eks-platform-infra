# Layer 30: Jenkins on a private EC2 behind an HTTPS ALB that only your IP can reach
# Read the other layers
locals {
  vpc_id          = var.vpc_id
  public_subnets  = var.public_subnet_ids
  private_subnets = var.private_subnet_ids
}

data "aws_route53_zone" "main" {
  name         = var.domain
  private_zone = false
}
