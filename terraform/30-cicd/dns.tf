resource "aws_route53_record" "jenkins" {
  count   = var.edge_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.jenkins_hostname
  type    = "A"
  alias {
    name                   = aws_lb.jenkins[0].dns_name
    zone_id                = aws_lb.jenkins[0].zone_id
    evaluate_target_health = true
  }
}
