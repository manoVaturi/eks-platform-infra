provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "weatherapp", Layer = "LAYER_NAME", ManagedBy = "terraform" }
  }
}
