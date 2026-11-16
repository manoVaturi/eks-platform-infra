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

variable "jenkins_hostname" {
  description = "Public host name of Jenkins."
  type        = string
  default     = "jenkins.manovaturi.com"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium" # 4 GB: the Terraform checks need more than the 2 GB of a t3.small
}

# The edge is the shared ALB and what exists only because of it. up.sh turns it on, down.sh off
variable "edge_enabled" {
  description = "Daily switch: true creates the shared ALB, its listeners, rules and DNS aliases; false removes them. Use the scripts, not a plain apply."
  type        = bool
  default     = true
}

# Who may open the Jenkins login page: one range per place you work from. Set in terraform.tfvars (git-ignored).
variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the Jenkins ALB, e.g. [\"1.2.3.4/32\", \"5.6.7.0/24\"]"
  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Give at least one range; each must be a valid CIDR and none may be 0.0.0.0/0."
  }
}

variable "vpc_id" {
  description = "VPC id (from layer 10-network)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet ids (from layer 10-network)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet ids (from layer 10-network)."
  type        = list(string)
}

variable "jenkins_ecr_push_policy_arn" {
  description = "ARN of the ECR push policy (from layer 20-persistent)."
  type        = string
}
