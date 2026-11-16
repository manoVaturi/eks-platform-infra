include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "network" {
  config_path = "../10-network"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000003", "subnet-00000004"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "persistent" {
  config_path = "../20-persistent"

  mock_outputs = {
    route53_zone_arn     = "arn:aws:route53:::hostedzone/Z00000000"
    vault_unseal_key_arn = "arn:aws:kms:eu-west-1:000000000000:key/00000000-0000-0000-0000-000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  region               = "eu-west-1"
  vpc_id               = dependency.network.outputs.vpc_id
  private_subnet_ids   = dependency.network.outputs.private_subnet_ids
  route53_zone_arn     = dependency.persistent.outputs.route53_zone_arn
  vault_unseal_key_arn = dependency.persistent.outputs.vault_unseal_key_arn
}
