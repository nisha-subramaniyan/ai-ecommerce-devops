terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}

variable "project" { type = string }
variable "instance_type" { type = string }
variable "ssh_public_key_path" { type = string }
variable "ssh_private_key_path" { type = string }
variable "admin_cidr" { type = string }

# Latest Ubuntu 22.04 LTS image published by Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Firewall: SSH only from YOUR IP; web on 80 for everyone. Everything else is closed.
resource "aws_security_group" "this" {
  name        = "${var.project}-sg"
  description = "SSH from admin, HTTP from anywhere"

  ingress {
    description = "SSH (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options { http_tokens = "required" } # IMDSv2 only (hardening)

  tags = { Name = "${var.project}-server", Project = var.project }
}

# Terraform hands the new server's IP to Ansible: infrastructure -> configuration.
resource "local_file" "inventory" {
  filename = "${path.root}/../ansible/inventory-aws.ini"
  content  = <<-EOT
    [shop_servers]
    ${aws_instance.this.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${var.ssh_private_key_path}
  EOT
}

output "public_ip" { value = aws_instance.this.public_ip }
output "inventory_path" { value = local_file.inventory.filename }
