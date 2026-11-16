# Container registry

resource "aws_ecr_repository" "weatherapp" {
  name = "weatherapp"

  # IMMUTABLE: a tag can never be overwritten, so Argo CD deploys what Jenkins tested
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }

  # Lets `terraform destroy` remove the repo even if it has images (the environment is torn down between sessions).
  force_delete = true
}

# Without a lifecycle policy, every build is stored (and billed) forever.
resource "aws_ecr_lifecycle_policy" "weatherapp" {
  repository = aws_ecr_repository.weatherapp.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 15 most recent images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
      action       = { type = "expire" }
    }]
  })
}
