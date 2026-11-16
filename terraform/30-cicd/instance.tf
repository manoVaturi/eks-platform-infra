# ---------- The instance ----------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  user_data              = file("${path.module}/user_data.sh")

  # Re-run user_data only when the script changes, and replace the instance then.
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only: blocks SSRF-style credential theft
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "weatherapp-jenkins" }

  # marks the root disk for the backup policy below
  volume_tags = { Backup = "jenkins-daily" }

  # A newer Ubuntu AMI must not replace Jenkins (its config is on this disk): update with apt
  lifecycle { ignore_changes = [ami] }
}
