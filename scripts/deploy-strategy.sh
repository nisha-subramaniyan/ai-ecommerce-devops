#!/usr/bin/env bash
# deploy-strategy.sh - demonstrate the three deployment strategies on Kubernetes.
#   ./scripts/deploy-strategy.sh rolling <tag>     rolling update of the Helm release (default strategy)
#   ./scripts/deploy-strategy.sh canary  <tag>     start a 1-replica canary running <tag> next to stable
#   ./scripts/deploy-strategy.sh promote <tag>     promote canary version to everyone, remove canary
#   ./scripts/deploy-strategy.sh bluegreen <tag>   deploy <tag> as "green", then flip the Service selector
#   ./scripts/deploy-strategy.sh rollback          helm rollback to previous revision
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NAMESPACE:-shop}"; REGISTRY="${REGISTRY:-localhost:5001}"
MODE="${1:?mode required}"; TAG="${2:-}"
HELM=(helm upgrade --install shop "$ROOT/helm/ecommerce" -n "$NS" --set image.registry="$REGISTRY" --wait --timeout 180s)

case "$MODE" in
  rolling)   # Kubernetes replaces pods gradually (maxUnavailable=0, maxSurge=1): zero downtime
    "${HELM[@]}" --set image.tag="$TAG"
    kubectl -n "$NS" rollout status deploy/shop-backend ;;
  canary)    # ~1 of N pods run the new version; watch Grafana/ELK, then promote or roll back
    "${HELM[@]}" --reuse-values --set canary.enabled=true --set canary.tag="$TAG"
    echo "Canary live. Check errors in Grafana/Kibana, then: $0 promote $TAG   (or: helm rollback shop -n $NS)" ;;
  promote)
    "${HELM[@]}" --reuse-values --set image.tag="$TAG" --set canary.enabled=false ;;
  bluegreen) # run both colours; traffic only moves when the Service selector flips
    "${HELM[@]}" --reuse-values --set blueGreen.enabled=true --set blueGreen.greenTag="$TAG"
    kubectl -n "$NS" rollout status deploy/shop-backend-green
    echo "Green is healthy. Flipping traffic to green..."
    "${HELM[@]}" --reuse-values --set blueGreen.active=green
    echo "Traffic on green. Instant rollback: ${HELM[*]} --reuse-values --set blueGreen.active=blue" ;;
  rollback)
    helm rollback shop -n "$NS" --wait ;;
  *) echo "unknown mode $MODE"; exit 2 ;;
esac
