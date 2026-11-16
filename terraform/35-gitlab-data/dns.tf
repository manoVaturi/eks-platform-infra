# ---------- DNS ----------

resource "aws_route53_record" "gitlab" {
  count   = var.edge_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.gitlab_hostname
  type    = "A"
  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }
}
