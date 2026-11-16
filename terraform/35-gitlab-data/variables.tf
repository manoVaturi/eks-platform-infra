variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "domain" {
  description = "The public DNS zone (it must already exist in Route 53)."
  type        = string
  default     = "manovaturi.com"
}

# Must match layer 30: up.sh and down.sh pass the same value to both
variable "edge_enabled" {
  description = "Daily switch: true creates the shared ALB, its listeners, rules and DNS aliases; false removes them. Use the scripts, not a plain apply."
  type        = bool
  default     = true
}

variable "gitlab_hostname" {
  description = "Public host name of GitLab."
  type        = string
  default     = "gitlab.manovaturi.com"
}

variable "data_volume_size_gb" {
  type        = number
  default     = 10
  description = "Can be grown later without downtime, never shrunk."
}

variable "vpc_id" {
  description = "VPC id (from layer 10-network)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet ids (from layer 10-network)."
  type        = list(string)
}

variable "nat_public_ips" {
  description = "NAT gateway public IPs (from layer 10-network); empty while the NAT is off."
  type        = list(string)
}

variable "wildcard_certificate_arn" {
  description = "Wildcard certificate ARN (from layer 20-persistent)."
  type        = string
}

variable "owner_cidrs" {
  description = "Your allowed IP ranges (from layer 30-cicd)."
  type        = list(string)
}

variable "alb_dns_name" {
  description = "ALB DNS name (layer 30-cicd); null while the edge is off."
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "ALB hosted zone id (layer 30-cicd); null while the edge is off."
  type        = string
  default     = null
}

variable "alb_listener_arn" {
  description = "ALB listener ARN (layer 30-cicd); null while the edge is off."
  type        = string
  default     = null
}

variable "alb_security_group_id" {
  description = "ALB security group id (layer 30-cicd); null while the edge is off."
  type        = string
  default     = null
}
