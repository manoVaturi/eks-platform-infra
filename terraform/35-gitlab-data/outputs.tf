output "gitlab_url" {
  description = "Public URL of GitLab."
  value       = "https://${var.gitlab_hostname}"
}
output "gitlab_hostname" {
  description = "Public host name of GitLab."
  value       = var.gitlab_hostname
}
output "data_volume_id" {
  description = "ID of the GitLab data volume."
  value       = aws_ebs_volume.data.id
}
output "subnet_id" {
  description = "Subnet that holds the GitLab server and its data volume."
  value       = local.subnet_id
}
output "target_group_arn" {
  description = "ARN of the ALB target group that sends traffic to GitLab."
  value       = aws_lb_target_group.gitlab.arn
}