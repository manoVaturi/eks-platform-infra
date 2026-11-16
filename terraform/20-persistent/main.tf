# Layer 20: long-lived resources that survive cluster teardown

data "aws_route53_zone" "main" {
  name         = var.domain
  private_zone = false
}
