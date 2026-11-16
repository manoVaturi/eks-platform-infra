data "aws_iam_role" "jenkins" {
  name = "weatherapp-jenkins"
}

resource "aws_iam_role" "ci_plan" {
  name = "weatherapp-ci-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = data.aws_iam_role.jenkins.arn }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "state_access" {
  name = "weatherapp-ci-plan-state"
  role = aws_iam_role.ci_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::mano-tf-state-bucket"
      },
      {
        Sid      = "WriteLockFilesOnly"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::mano-tf-state-bucket/*.tflock"
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_assume_ci_plan" {
  name = "weatherapp-jenkins-assume-ci-plan"
  role = data.aws_iam_role.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.ci_plan.arn
    }]
  })
}
