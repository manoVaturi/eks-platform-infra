resource "aws_lb_target_group_attachment" "gitlab" {
  target_group_arn = local.target_group
  target_id        = aws_instance.gitlab.id
  port             = 80
}
