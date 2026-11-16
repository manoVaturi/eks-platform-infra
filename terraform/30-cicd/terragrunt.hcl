include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "network" {
  config_path = "../10-network"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    public_subnet_ids  = ["subnet-00000001", "subnet-00000002"]
    private_subnet_ids = ["subnet-00000003", "subnet-00000004"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "persistent" {
  config_path = "../20-persistent"

  mock_outputs = {
    jenkins_ecr_push_policy_arn = "arn:aws:iam::000000000000:policy/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  region                      = "eu-west-1"
  vpc_id                      = dependency.network.outputs.vpc_id
  public_subnet_ids           = dependency.network.outputs.public_subnet_ids
  private_subnet_ids          = dependency.network.outputs.private_subnet_ids
  jenkins_ecr_push_policy_arn = dependency.persistent.outputs.jenkins_ecr_push_policy_arn
}
