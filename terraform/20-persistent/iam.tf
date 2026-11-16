# ---------- CI permissions (least privilege) ----------

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken cannot be scoped to a repository; AWS requires "*".
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything else is limited to THIS one repository.
  statement {
    sid = "PushPullWeatherappImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.weatherapp.arn]
  }
}

resource "aws_iam_policy" "jenkins_ecr_push" {
  name        = "weatherapp-jenkins-ecr-push"
  description = "Allows CI to push/pull images to the weatherapp ECR repo only"
  policy      = data.aws_iam_policy_document.ecr_push.json
}
