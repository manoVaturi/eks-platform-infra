provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "weatherapp", Layer = "00-bootstrap", ManagedBy = "terraform" }
  }
}
