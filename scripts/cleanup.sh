#!/usr/bin/env bash
# cleanup.sh - reclaim disk space and report system health.
#   ./scripts/cleanup.sh            (safe: dangling images, stopped containers, old logs/backups)
#   ./scripts/cleanup.sh --deep     (also removes ALL unused images and build cache)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== System check =="
echo "Disk:";   df -h / | tail -1
echo "Memory:"; free -h | sed -n '1,2p'
echo "Load:    $(cut -d' ' -f1-3 /proc/loadavg)"

echo "== Docker cleanup =="
docker container prune -f
docker image prune -f
[ "${1:-}" = "--deep" ] && { docker image prune -af; docker builder prune -af; }

echo "== Old files =="
find "$ROOT/backups" -name '*.sql.gz' -mtime +14 -print -delete 2>/dev/null || true
find "$ROOT" -name '*.log' -mtime +7 -not -path '*/node_modules/*' -print -delete 2>/dev/null || true

echo "== Done =="
docker system df
