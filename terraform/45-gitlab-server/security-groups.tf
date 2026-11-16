# ---------- Network: only the load balancer may talk to GitLab ----------

resource "aws_security_group" "gitlab" {
  name        = "weatherapp-gitlab"
  description = "GitLab instance: only the ALB may connect"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_from_alb" {
  security_group_id            = aws_security_group.gitlab.id
  referenced_security_group_id = local.alb_sg_id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"

  lifecycle {
    precondition {
      condition     = local.alb_sg_id != null
      error_message = "The edge (shared ALB) is switched off, so GitLab has nothing to sit behind. Run scripts/up.sh, which turns the edge on first."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "gitlab_out" {
  security_group_id = aws_security_group.gitlab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # egress only; leaves through the NAT gateway (docker image, apt, calls to Jenkins)
}

# The ALB egress is limited to Jenkins: let it reach GitLab too (it goes with the instance)
resource "aws_vpc_security_group_egress_rule" "alb_to_gitlab" {
  security_group_id            = local.alb_sg_id
  referenced_security_group_id = aws_security_group.gitlab.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}
