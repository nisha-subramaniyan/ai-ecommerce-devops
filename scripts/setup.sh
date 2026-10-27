#!/usr/bin/env bash
# setup.sh - prepare a fresh Ubuntu/Debian machine (or WSL2 Ubuntu) for this project.
# Installs: docker, git, node, python3, kubectl, kind, helm, terraform, ansible, trivy, gitleaks.
# Safe to re-run: every tool is skipped if it is already installed.
# Usage: ./scripts/setup.sh
set -euo pipefail

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"   # amd64 or arm64

log "Updating apt and installing base packages"
$SUDO apt-get update -y
$SUDO apt-get install -y curl wget git unzip jq ca-certificates gnupg lsb-release \
  software-properties-common python3 python3-pip python3-venv nodejs npm

if ! have docker; then
  log "Installing Docker Engine"
  curl -fsSL https://get.docker.com | $SUDO sh
  $SUDO usermod -aG docker "${SUDO_USER:-$USER}" || true
  log "NOTE: log out/in (or run 'newgrp docker') so the docker group takes effect"
fi

if ! have kubectl; then
  log "Installing kubectl"
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
  $SUDO install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

if ! have kind; then
  log "Installing kind (Kubernetes-in-Docker, free local cluster)"
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-${ARCH}"
  $SUDO install -m 0755 /tmp/kind /usr/local/bin/kind
fi

if ! have helm; then
  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! have terraform; then
  log "Installing Terraform"
  curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg --yes
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -y && $SUDO apt-get install -y terraform
fi

if ! have ansible; then
  log "Installing Ansible"
  $SUDO apt-get install -y ansible
fi

if ! have trivy; then
  log "Installing Trivy (image/dependency scanner)"
  curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | $SUDO sh -s -- -b /usr/local/bin
fi

if ! have gitleaks; then
  log "Installing gitleaks (secret scanner)"
  GL_ARCH="x64"; [ "$ARCH" = "arm64" ] && GL_ARCH="arm64"
  GL_VER="8.18.4"
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_linux_${GL_ARCH}.tar.gz" \
    | $SUDO tar -xz -C /usr/local/bin gitleaks
fi

log "Installed versions:"
for t in git docker node kubectl kind helm terraform ansible trivy gitleaks; do
  printf '  %-10s' "$t"; ( "$t" --version 2>/dev/null || "$t" version --client 2>/dev/null || true ) | head -1
done
log "Done. Next: ./scripts/deploy.sh local"
