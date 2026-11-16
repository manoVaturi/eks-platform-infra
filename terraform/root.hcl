# terraform/root.hcl
locals {
  region = "eu-west-1"

  # The state key of every layer. These are the ORIGINAL keys: changing one points the layer at an empty state.
  state_keys = {
    "10-network"       = "network/terraform.tfstate"
    "20-persistent"    = "persistent/terraform.tfstate"
    "30-cicd"          = "cicd/terraform.tfstate"
    "32-ci-plan"       = "ci-plan/terraform.tfstate"
    "35-gitlab-data"   = "gitlab-persistent/terraform.tfstate"
    "40-eks"           = "eks/terraform.tfstate"
    "45-gitlab-server" = "gitlab/terraform.tfstate"
  }

  # Which file in _shared/ becomes versions.tf. Default versions.tf.tpl; 30-cicd also needs the http provider.
  versions_files = {
    "30-cicd" = "versions-http.tf.tpl"
  }
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "mano-tf-state-bucket"
    region       = local.region
    use_lockfile = true
    key          = local.state_keys[path_relative_to_include()]
  }
}

# providers.tf and versions.tf are the same in every layer, so they live once in _shared/.
# LAYER_NAME is replaced by the folder name (the Layer tag). scripts/tf.sh uses the same files for validate/lint/scan.
generate "provider" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = replace(file("${get_parent_terragrunt_dir()}/_shared/providers.tf.tpl"), "LAYER_NAME", path_relative_to_include())
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = file("${get_parent_terragrunt_dir()}/_shared/${lookup(local.versions_files, path_relative_to_include(), "versions.tf.tpl")}")
}
