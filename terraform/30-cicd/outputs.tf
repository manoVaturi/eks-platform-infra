output "jenkins_url" {
  description = "Public URL of Jenkins."
  value       = "https://${var.jenkins_hostname}"
}
output "instance_id" {
  description = "EC2 instance ID of the server."
  value       = aws_instance.jenkins.id
}
output "ssm_command" {
  description = "Command that opens a shell on the server through SSM (no SSH, no open port)."
  value       = "aws ssm start-session --target ${aws_instance.jenkins.id} --region ${var.region}"
}
# Read by the GitLab layers, null while the edge is off
output "edge_enabled" {
  description = "Whether the shared ALB and its rules currently exist."
  value       = var.edge_enabled
}
output "alb_arn" {
  description = "ARN of the shared ALB (null while the edge is off)."
  value       = try(aws_lb.jenkins[0].arn, null)
}
output "alb_dns_name" {
  description = "DNS name of the shared ALB (null while the edge is off)."
  value       = try(aws_lb.jenkins[0].dns_name, null)
}
output "alb_zone_id" {
  description = "Route 53 zone ID of the shared ALB, for alias records (null while the edge is off)."
  value       = try(aws_lb.jenkins[0].zone_id, null)
}
output "alb_listener_arn" {
  description = "ARN of the HTTPS listener of the shared ALB (null while the edge is off)."
  value       = try(aws_lb_listener.https[0].arn, null)
}
output "alb_security_group_id" {
  description = "Security group of the shared ALB (null while the edge is off)."
  value       = try(aws_security_group.alb[0].id, null)
}
output "allowed_cidrs" {
  description = "The IP ranges that may reach the ALB and the EKS API."
  value       = var.allowed_cidrs
}