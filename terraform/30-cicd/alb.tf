# ---------- Load balancer ----------

resource "aws_lb" "jenkins" {
  count              = var.edge_enabled ? 1 : 0
  name               = "weatherapp-jenkins"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = local.public_subnets
}

resource "aws_lb_target_group" "jenkins" {
  name     = "weatherapp-jenkins"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    path    = "/login"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
}

resource "aws_lb_listener" "https" {
  count             = var.edge_enabled ? 1 : 0
  load_balancer_arn = aws_lb.jenkins[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.jenkins.certificate_arn

  # Default-deny: anything that matches no rule below gets 403.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# You: every path.
resource "aws_lb_listener_rule" "allow_owner" {
  count        = var.edge_enabled ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
  condition {
    source_ip { values = var.allowed_cidrs }
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.edge_enabled ? 1 : 0
  load_balancer_arn = aws_lb.jenkins[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
