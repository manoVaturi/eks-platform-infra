output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}
output "cluster_endpoint" {
  description = "URL of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}
output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider (the trust anchor of the IRSA roles)."
  value       = module.eks.oidc_provider_arn
}
output "node_security_group_id" {
  description = "Security group of the EKS nodes."
  value       = module.eks.node_security_group_id
}
output "kubeconfig_command" {
  description = "Command that writes this cluster into your kubeconfig."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}