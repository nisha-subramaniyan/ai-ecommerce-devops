variable "target" {
  description = "Where to build the platform: 'local' (free kind cluster in Docker) or 'aws' (EC2 + k3s)."
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "aws"], var.target)
    error_message = "target must be 'local' or 'aws'."
  }
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "shop"
}

# ---- aws ----
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "instance_type" {
  description = "t3.micro / t2.micro are Free-Tier eligible (check your account's free-tier rules)."
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key_path" {
  description = "Your public SSH key, installed on the server."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH in, e.g. 203.0.113.4/32 (your IP). Never use 0.0.0.0/0 for SSH."
  type        = string
  default     = "127.0.0.1/32"
}

variable "ssh_private_key_path" {
  description = "Private key matching ssh_public_key_path, written into the Ansible inventory."
  type        = string
  default     = "~/.ssh/id_rsa"
}
