output "role_arn" {
  description = "ARN of the read-only role that the Jenkins plan stage assumes."
  value       = aws_iam_role.ci_plan.arn
}