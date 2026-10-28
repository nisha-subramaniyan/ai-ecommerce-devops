#!/usr/bin/env bash
# deploy.sh - one command to run the application in different targets.
#   ./scripts/deploy.sh compose            -> Docker Compose on localhost:8081
#   ./scripts/deploy.sh cluster            -> only create the registry + kind cluster + ingress (no app)
#   ./scripts/deploy.sh build [tag]        -> build and push both images to the local registry
#   ./scripts/deploy.sh local [tag]        -> cluster + build + Helm release (needs: kind, kubectl, helm, docker)
#   ./scripts/deploy.sh down               -> tear everything down
# Environment: REGISTRY (default localhost:5001), NAMESPACE (default shop)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-localhost:5001}"
NAMESPACE="${NAMESPACE:-shop}"
CLUSTER="${CLUSTER:-shop}"
TARGET="${1:-compose}"
TAG="${2:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo latest)}"

log() { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }

build_images() {
  log "Building images (tag: $TAG)"
  docker build -f "$ROOT/docker/Dockerfile"          --build-arg APP_VERSION="$TAG" -t "$REGISTRY/shop-backend:$TAG"  "$ROOT"
  docker build -f "$ROOT/docker/Dockerfile.frontend" -t "$REGISTRY/shop-frontend:$TAG" "$ROOT"
}

start_registry_and_cluster() {
  # Local registry (container) so the cluster pulls images exactly like it would from a real registry.
  if [ "$(docker inspect -f '{{.State.Running}}' kind-registry 2>/dev/null || true)" != "true" ]; then
    log "Starting local registry on :5001"
    docker run -d --restart=always -p 127.0.0.1:5001:5000 --network bridge --name kind-registry registry:2
  fi
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    log "Creating kind cluster '$CLUSTER'"
    kind create cluster --name "$CLUSTER" --config "$ROOT/kubernetes/kind-config.yaml"
  fi
  # Tell every node's containerd how to reach the registry
  for node in $(kind get nodes --name "$CLUSTER"); do
    docker exec "$node" mkdir -p /etc/containerd/certs.d/localhost:5001
    cat <<EOF | docker exec -i "$node" tee /etc/containerd/certs.d/localhost:5001/hosts.toml >/dev/null
[host."http://kind-registry:5000"]
EOF
  done
  docker network connect kind kind-registry 2>/dev/null || true
}

install_ingress() {
  if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
    log "Installing ingress-nginx"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  fi
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s
}

case "$TARGET" in
  compose)
    docker compose -f "$ROOT/docker/docker-compose.yml" up -d --build
    "$ROOT/scripts/health-check.sh" compose
    log "Open http://localhost:8081"
    ;;
  cluster)
    start_registry_and_cluster
    install_ingress
    log "Cluster ready. Next: ./scripts/deploy.sh local"
    ;;
  build)
    build_images
    docker push "$REGISTRY/shop-backend:$TAG"
    docker push "$REGISTRY/shop-frontend:$TAG"
    log "Pushed $REGISTRY/shop-{backend,frontend}:$TAG"
    ;;
  local)
    start_registry_and_cluster
    install_ingress
    build_images
    docker push "$REGISTRY/shop-backend:$TAG"
    docker push "$REGISTRY/shop-frontend:$TAG"
    log "Deploying with Helm"
    helm upgrade --install shop "$ROOT/helm/ecommerce" -n "$NAMESPACE" --create-namespace \
      --set image.registry="$REGISTRY" --set image.tag="$TAG" --wait --timeout 180s
    "$ROOT/scripts/health-check.sh" k8s
    log "Open http://localhost:8081  (ingress) - rollout history: helm history shop -n $NAMESPACE"
    ;;
  down)
    docker compose -f "$ROOT/docker/docker-compose.yml" down 2>/dev/null || true
    kind delete cluster --name "$CLUSTER" 2>/dev/null || true
    docker rm -f kind-registry 2>/dev/null || true
    log "Everything removed"
    ;;
  *) echo "usage: $0 {compose|cluster|build|local|down} [tag]"; exit 2 ;;
esac
