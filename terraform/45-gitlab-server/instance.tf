# ---------- The instance ----------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "gitlab" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.gitlab.id]
  iam_instance_profile   = aws_iam_instance_profile.gitlab.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname         = local.gitlab_hostname
    image            = var.gitlab_image
    volume_id_nodash = replace(local.volume_id, "-", "")
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 20 # OS + the GitLab image, rebuilt on every boot
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "weatherapp-gitlab" }
}

# stop_instance_before_detaching: shut down cleanly so the data volume stays consistent
resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  volume_id                      = local.volume_id
  instance_id                    = aws_instance.gitlab.id
  stop_instance_before_detaching = true
}
