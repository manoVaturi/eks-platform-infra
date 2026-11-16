output "instance_id" {
  description = "EC2 instance ID of the server."
  value       = aws_instance.gitlab.id
}
output "ssm_command" {
  description = "Command that opens a shell on the server through SSM (no SSH, no open port)."
  value       = "aws ssm start-session --target ${aws_instance.gitlab.id} --region ${var.region}"
}