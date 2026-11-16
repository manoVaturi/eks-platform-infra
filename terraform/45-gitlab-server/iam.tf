# ---------- IAM: instance role (SSM shell access, no keys, no SSH) ----------

resource "aws_iam_role" "gitlab" {
  name = "weatherapp-gitlab"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gitlab.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "gitlab" {
  name = "weatherapp-gitlab"
  role = aws_iam_role.gitlab.name
}
