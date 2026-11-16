# ---------- Security groups ----------

resource "aws_security_group" "alb" {
  count       = var.edge_enabled ? 1 : 0
  name        = "weatherapp-jenkins-alb"
  description = "Jenkins ALB: HTTPS only from the allowed CIDR"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each          = var.edge_enabled ? toset(var.allowed_cidrs) : toset([])
  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = var.edge_enabled ? toset(var.allowed_cidrs) : toset([])
  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp" # only to redirect to 443
}

resource "aws_security_group" "jenkins" {
  name        = "weatherapp-jenkins"
  description = "Jenkins instance: only the ALB may connect"
  vpc_id      = local.vpc_id
}

# Referencing the ALB's SG (not a CIDR) means "only that load balancer".
resource "aws_vpc_security_group_ingress_rule" "jenkins_from_alb" {
  count                        = var.edge_enabled ? 1 : 0
  security_group_id            = aws_security_group.jenkins.id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_out" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # egress only; leaves through the NAT gateway (apt, GitLab, ECR, Slack)
}

resource "aws_vpc_security_group_egress_rule" "alb_to_jenkins" {
  count                        = var.edge_enabled ? 1 : 0
  security_group_id            = aws_security_group.alb[0].id
  referenced_security_group_id = aws_security_group.jenkins.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}
