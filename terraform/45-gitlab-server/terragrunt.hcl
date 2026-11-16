include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "network" {
  config_path = "../10-network"

  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "gitlab_persistent" {
  config_path = "../35-gitlab-data"

  mock_outputs = {
    subnet_id        = "subnet-00000003"
    data_volume_id   = "vol-00000000"
    target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:000000000000:targetgroup/mock/0000000000000000"
    gitlab_hostname  = "gitlab.example.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "cicd" {
  config_path = "../30-cicd"

  mock_outputs = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  region           = "eu-west-1"
  vpc_id           = dependency.network.outputs.vpc_id
  subnet_id        = dependency.gitlab_persistent.outputs.subnet_id
  data_volume_id   = dependency.gitlab_persistent.outputs.data_volume_id
  target_group_arn = dependency.gitlab_persistent.outputs.target_group_arn
  gitlab_hostname  = dependency.gitlab_persistent.outputs.gitlab_hostname

  # Absent while the edge is off: try() gives null, like the old try() on remote state
  alb_security_group_id = try(dependency.cicd.outputs.alb_security_group_id, null)
}
