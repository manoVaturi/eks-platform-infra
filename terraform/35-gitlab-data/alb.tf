# ---------- Load balancer wiring ----------

# The wildcard certificate (layer 20) already covers gitlab.manovaturi.com
resource "aws_lb_listener_certificate" "wildcard" {
  count           = var.edge_enabled ? 1 : 0
  listener_arn    = local.listener_arn
  certificate_arn = var.wildcard_certificate_arn
}

resource "aws_lb_target_group" "gitlab" {
  name                 = "weatherapp-gitlab"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/users/sign_in" # answers 200 once GitLab has finished starting (3-5 minutes)
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

# Priority 5 on purpose: the Jenkins rule allow_owner (10) matches any host from your IP
resource "aws_lb_listener_rule" "gitlab" {
  count        = var.edge_enabled ? 1 : 0
  listener_arn = local.listener_arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab.arn
  }
  condition {
    host_header { values = [var.gitlab_hostname] }
  }
  condition {
    # You, plus the NAT gateway (Jenkins and the EKS pods reach GitLab through it).
    source_ip { values = concat(local.owner_cidrs, local.nat_cidrs) }
  }
}

# The ALB security group is the network door: allow the NAT gateway in
resource "aws_vpc_security_group_ingress_rule" "alb_https_nat" {
  for_each          = var.edge_enabled ? toset(local.nat_cidrs) : toset([])
  security_group_id = local.alb_sg_id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "Jenkins and EKS reaching GitLab through the NAT gateway"
}

# GitLab -> Jenkins webhooks arrive through the NAT gateway, allowed only on the webhook paths

data "aws_lb_target_group" "jenkins" {
  name = "weatherapp-jenkins"
}

resource "aws_lb_listener_rule" "gitlab_webhook_to_jenkins" {
  count        = var.edge_enabled ? 1 : 0
  listener_arn = local.listener_arn
  priority     = 40 # Jenkins rules use 10 and 20+; GitLab host rule is 5

  action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.jenkins.arn
  }
  condition {
    source_ip { values = local.nat_cidrs }
  }
  condition {
    path_pattern { values = ["/gitlab-webhook/*", "/project/*", "/multibranch-webhook-trigger/*"] }
  }
}
