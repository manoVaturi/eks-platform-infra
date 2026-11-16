variable "region" {
  description = "AWS region of the whole project."
  type        = string
  default     = "eu-west-1"
}

variable "instance_type" {
  type        = string
  default     = "t3a.large" # 2 vCPU, 8 GB
  description = "GitLab is memory-hungry; do not go below 4 GB."
}

# Pinned: upgrade GitLab through its supported path, never :latest
variable "gitlab_image" {
  description = "GitLab CE container image and tag run on the GitLab server."
  type        = string
  default     = "gitlab/gitlab-ce:19.5.3-ce.0"
}

variable "vpc_id" {
  description = "VPC id (from layer 10-network)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet of the data volume (from layer 35-gitlab-data)."
  type        = string
}

variable "data_volume_id" {
  description = "GitLab data volume id (from layer 35-gitlab-data)."
  type        = string
}

variable "target_group_arn" {
  description = "GitLab target group ARN (from layer 35-gitlab-data)."
  type        = string
}

variable "gitlab_hostname" {
  description = "GitLab hostname (from layer 35-gitlab-data)."
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group id (layer 30-cicd); null while the edge is off."
  type        = string
  default     = null
}
