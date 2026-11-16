# Layer 40: the Kubernetes cluster, destroyed every night (EKS about $0.10/h plus the node)
# ---------- The cluster ----------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.allowed_cidrs
  endpoint_private_access      = true # nodes talk to the API privately, inside the VPC

  # Whoever runs terraform apply becomes cluster admin (EKS access entries)
  enable_cluster_creator_admin_permissions = true

  # Control-plane logs: where to look when something is wrong with auth or scheduling.
  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver     = {}
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  eks_managed_node_groups = {
    spot = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.large", "t3a.large", "m5.large"] # several types = better Spot availability
      capacity_type  = "SPOT"                                # ~70% cheaper; can be reclaimed, workloads tolerate a node replacement

      # Vault's data volume lives in eu-west-1a, so the node must too (private_subnet_ids[0] is the zone-a subnet).
      subnet_ids = [var.private_subnet_ids[0]]

      min_size     = 1
      max_size     = 2
      desired_size = 1

      disk_size = 30
    }
  }
}
