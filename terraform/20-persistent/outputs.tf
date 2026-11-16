output "ecr_repository_url" {
  description = "URL of the ECR repository that holds the app image."
  value       = aws_ecr_repository.weatherapp.repository_url
}
output "ecr_repository_arn" {
  description = "ARN of the ECR repository that holds the app image."
  value       = aws_ecr_repository.weatherapp.arn
}
output "jenkins_ecr_push_policy_arn" {
  description = "ARN of the IAM policy that lets Jenkins push images to ECR."
  value       = aws_iam_policy.jenkins_ecr_push.arn
}
output "wildcard_certificate_arn" {
  description = "ARN of the validated wildcard certificate for the domain."
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}
output "route53_zone_arn" {
  description = "ARN of the Route 53 hosted zone."
  value       = data.aws_route53_zone.main.arn
}
output "route53_zone_id" {
  description = "ID of the Route 53 hosted zone."
  value       = data.aws_route53_zone.main.zone_id
}
output "waf_acl_arn" {
  description = "ARN of the WAF web ACL attached to the app ALB."
  value       = aws_wafv2_web_acl.main.arn
}
output "vault_unseal_key_arn" {
  description = "ARN of the KMS key that auto-unseals Vault."
  value       = aws_kms_key.vault_unseal.arn
}
output "vault_data_volume_id" {
  description = "ID of the EBS volume that holds Vault's data (used by the PersistentVolume in the gitops repo)."
  value       = aws_ebs_volume.vault_data.id
}