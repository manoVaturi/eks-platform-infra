variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster; also the prefix of the roles and tags created for it."
  type        = string
  default     = "weatherapp"
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS cluster."
  type        = string
  default     = "1.36"
}

# The API endpoint is public (so kubectl works from your laptop) but only for your ranges.
variable "allowed_cidrs" {
  description = "IP ranges (CIDR) allowed to reach the ALB and the EKS API; the scripts add your current range each day. 0.0.0.0/0 is refused."
  type        = list(string)
  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Give at least one range; each must be a valid CIDR and none may be 0.0.0.0/0."
  }
}

variable "vpc_id" {
  description = "VPC id (from layer 10-network)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet ids (from layer 10-network)."
  type        = list(string)
}

variable "route53_zone_arn" {
  description = "Route53 zone ARN (from layer 20-persistent)."
  type        = string
}

variable "vault_unseal_key_arn" {
  description = "KMS key ARN for Vault auto-unseal (from layer 20-persistent)."
  type        = string
}
