output "state_bucket" {
  description = "Name of the S3 bucket that holds the Terraform state."
  value       = aws_s3_bucket.tfstate.id
}