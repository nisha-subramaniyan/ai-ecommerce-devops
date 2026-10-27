output "target" {
  value = var.target
}

output "kubeconfig_path" {
  description = "kubeconfig of the local kind cluster (use: export KUBECONFIG=<this>)"
  value       = var.target == "local" ? module.kind_cluster[0].kubeconfig_path : null
}

output "server_public_ip" {
  description = "Public IP of the AWS server (target = aws)"
  value       = var.target == "aws" ? module.aws_server[0].public_ip : null
}

output "ansible_inventory_path" {
  description = "Generated Ansible inventory for the AWS server"
  value       = var.target == "aws" ? module.aws_server[0].inventory_path : null
}
