# Layer 35: the persistent parts of GitLab (data volume, ALB rules, DNS), never destroyed by down.sh
# Read the other layers

locals {
  # The ALB outputs are absent while the edge is off, so read them with try()
  vpc_id    = var.vpc_id
  subnet_id = var.private_subnet_ids[0]
  nat_cidrs = [for ip in var.nat_public_ips : "${ip}/32"]

  alb_dns_name = var.alb_dns_name
  alb_zone_id  = var.alb_zone_id
  listener_arn = var.alb_listener_arn
  alb_sg_id    = var.alb_security_group_id
  owner_cidrs  = var.owner_cidrs
}

# The volume must be in the same availability zone as the instance, which uses this subnet.
data "aws_subnet" "gitlab" {
  id = local.subnet_id
}

data "aws_route53_zone" "main" {
  name         = var.domain
  private_zone = false
}
