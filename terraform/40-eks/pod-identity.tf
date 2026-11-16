# IAM for the pods that call AWS, through Pod Identity: the EBS CSI driver, the ALB controller and ExternalDNS.
# Each role is tied to one ServiceAccount (namespace and name) by an association; the chart must create a
# ServiceAccount with exactly that name (see values/platform in the gitops repo).

# IAM for the EBS CSI driver

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {
    ebs-csi = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

# Watches Ingress objects and creates/updates the real AWS ALB, listeners, target groups.
module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${var.cluster_name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    lb-controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# ExternalDNS writes Route53 records, restricted to our hosted zone
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                          = "${var.cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [var.route53_zone_arn]

  associations = {
    external-dns = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns"
    }
  }
}
