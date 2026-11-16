# IRSA vault: a role that only ONE ServiceAccount (vault/vault) in THIS cluster may assume

data "aws_iam_policy_document" "irsa_vault_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # which ServiceAccount: namespace and name must both match
    condition {
      test     = "StringEquals"
      variable = format("%s:sub", module.eks.oidc_provider)
      values   = ["system:serviceaccount:vault:vault"]
    }

    # the token must be meant for STS
    condition {
      test     = "StringEquals"
      variable = format("%s:aud", module.eks.oidc_provider)
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "irsa_vault_permissions" {
  statement {
    sid       = "VaultAutoUnseal"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    resources = [var.vault_unseal_key_arn]
  }
}

resource "aws_iam_role" "irsa_vault" {
  name               = format("%s-vault", var.cluster_name)
  assume_role_policy = data.aws_iam_policy_document.irsa_vault_trust.json
}

resource "aws_iam_role_policy" "irsa_vault" {
  name   = "vault-unseal"
  role   = aws_iam_role.irsa_vault.id
  policy = data.aws_iam_policy_document.irsa_vault_permissions.json
}

output "irsa_vault_role_arn" {
  description = "ARN of the IAM role the Vault pod assumes (IRSA) to use the unseal KMS key."
  value       = aws_iam_role.irsa_vault.arn
}