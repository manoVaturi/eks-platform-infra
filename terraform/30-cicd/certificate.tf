# ---------- TLS certificate (ACM, DNS-validated) ----------

resource "aws_acm_certificate" "jenkins" {
  domain_name       = var.jenkins_hostname
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

# ACM proves we own the domain by looking for these CNAME records.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.jenkins.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  }
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "jenkins" {
  certificate_arn         = aws_acm_certificate.jenkins.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
