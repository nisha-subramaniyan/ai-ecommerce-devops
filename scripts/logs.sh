#!/usr/bin/env bash
# logs.sh - log management helper: tail, show only errors, or rotate local log files.
#   ./scripts/logs.sh tail [compose|k8s]
#   ./scripts/logs.sh errors [compose|k8s]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD="${1:-tail}"; MODE="${2:-compose}"
src() {
  if [ "$MODE" = "k8s" ]; then kubectl -n "${NAMESPACE:-shop}" logs -l app=shop-backend --tail=200 "$@"
  else docker compose -f "$ROOT/docker/docker-compose.yml" logs backend --tail=200 "$@"; fi
}
case "$CMD" in
  tail)   src -f ;;
  errors) src | grep -E '"level":"error"' || echo "no errors found" ;;
  *) echo "usage: $0 {tail|errors} [compose|k8s]"; exit 2 ;;
esac
