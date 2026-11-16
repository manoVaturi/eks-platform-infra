# ---------- IAM: instance role (no access keys) ----------

resource "aws_iam_role" "jenkins" {
  name = "weatherapp-jenkins"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# SSM Session Manager = shell access without SSH keys or open port 22.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.jenkins.name
  policy_arn = var.jenkins_ecr_push_policy_arn
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "weatherapp-jenkins"
  role = aws_iam_role.jenkins.name
}
