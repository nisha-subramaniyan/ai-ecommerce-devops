#!/usr/bin/env bash
# health-check.sh - verify a deployment is really serving traffic. Exit code 0 = healthy.
#   ./scripts/health-check.sh compose|k8s|<url>
# Used by Jenkins as the "Health Check" stage and by humans after deploying.
set -uo pipefail

TARGET="${1:-compose}"
case "$TARGET" in
  compose) URL="http://localhost:8080" ;;
  k8s)     URL="http://localhost:8081" ;;   # kind maps ingress to host port 8081
  http*)   URL="$TARGET" ;;
  *) echo "usage: $0 {compose|k8s|<url>}"; exit 2 ;;
esac

RETRIES="${RETRIES:-30}"; SLEEP="${SLEEP:-4}"
check() { # $1=path $2=expected substring
  local body; body="$(curl -fsS -m 5 "$URL$1" 2>/dev/null)" || return 1
  [[ "$body" == *"$2"* ]]
}

for ((i=1; i<=RETRIES; i++)); do
  if check "/health" "ok" && check "/api/products" "Headphones"; then
    echo "[health] OK: $URL (attempt $i)"
    exit 0
  fi
  echo "[health] waiting for $URL ... ($i/$RETRIES)"
  sleep "$SLEEP"
done
echo "[health] FAILED: $URL did not become healthy" >&2
exit 1
