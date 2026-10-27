terraform {
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.6" }
  }
}

variable "cluster_name" { type = string }

# Terraform creates the same cluster that scripts/deploy.sh would, but declaratively.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = pathexpand("~/.kube/${var.cluster_name}-config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      extra_port_mappings {
        container_port = 80
        host_port      = 8081
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 8443
      }
    }
    node { role = "worker" }
    node { role = "worker" }
  }
}

output "kubeconfig_path" { value = kind_cluster.this.kubeconfig_path }
