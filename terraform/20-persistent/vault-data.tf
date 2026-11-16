resource "aws_ebs_volume" "vault_data" {
  availability_zone = var.vault_data_az
  size              = 2
  type              = "gp3"
  encrypted         = true

  # Backup=jenkins-daily gets the daily snapshot from layer 30
  tags = { Name = "weatherapp-vault-data", Backup = "jenkins-daily" }

  lifecycle {
    prevent_destroy = true
  }
}
