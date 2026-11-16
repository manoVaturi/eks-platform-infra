# Vault auto-unseal: the key that wraps Vault's master key (see layer 40, irsa.tf)

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal: wraps Vault's master key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/weatherapp-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}
