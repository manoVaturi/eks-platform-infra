# Layer 45: the GitLab instance, destroyed by down.sh. Its data lives on the layer 35 volume
# Read the other layers

locals {
  vpc_id          = var.vpc_id
  subnet_id       = var.subnet_id # same subnet (so same AZ) as the volume
  volume_id       = var.data_volume_id
  target_group    = var.target_group_arn
  gitlab_hostname = var.gitlab_hostname
  alb_sg_id       = var.alb_security_group_id
}
