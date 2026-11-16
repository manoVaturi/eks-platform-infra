# ---------- Data volume ----------

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.gitlab.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  # Backup=jenkins-daily gets the daily snapshot from layer 30
  tags = { Name = "weatherapp-gitlab-data", Backup = "jenkins-daily" }

  lifecycle {
    prevent_destroy = true # destroy fails on purpose: this holds all the code
  }
}
