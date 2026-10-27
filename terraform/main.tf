# One codebase, two targets. `count` switches a module on or off based on var.target.
module "kind_cluster" {
  source           = "./modules/kind-cluster"
  count            = var.target == "local" ? 1 : 0
  cluster_name     = var.project
}

module "aws_server" {
  source               = "./modules/aws-ec2"
  count                = var.target == "aws" ? 1 : 0
  project              = var.project
  instance_type        = var.instance_type
  ssh_public_key_path  = var.ssh_public_key_path
  ssh_private_key_path = var.ssh_private_key_path
  admin_cidr           = var.admin_cidr
}
