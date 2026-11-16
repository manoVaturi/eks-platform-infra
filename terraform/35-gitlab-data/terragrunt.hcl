include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "network" {
  config_path = "../10-network"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000003", "subnet-00000004"]
    nat_public_ips     = []
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "persistent" {
  config_path = "../20-persistent"

  mock_outputs = {
    wildcard_certificate_arn = "arn:aws:acm:eu-west-1:000000000000:certificate/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "cicd" {
  config_path = "../30-cicd"

  mock_outputs = {
    allowed_cidrs = ["192.0.2.0/24"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  region                   = "eu-west-1"
  vpc_id                   = dependency.network.outputs.vpc_id
  private_subnet_ids       = dependency.network.outputs.private_subnet_ids
  nat_public_ips           = dependency.network.outputs.nat_public_ips
  wildcard_certificate_arn = dependency.persistent.outputs.wildcard_certificate_arn
  owner_cidrs              = dependency.cicd.outputs.allowed_cidrs

  # These outputs do not exist while the edge is off: try() gives null, like the old try() on remote state
  alb_dns_name          = try(dependency.cicd.outputs.alb_dns_name, null)
  alb_zone_id           = try(dependency.cicd.outputs.alb_zone_id, null)
  alb_listener_arn      = try(dependency.cicd.outputs.alb_listener_arn, null)
  alb_security_group_id = try(dependency.cicd.outputs.alb_security_group_id, null)
}
