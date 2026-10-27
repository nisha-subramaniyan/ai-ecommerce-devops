#!/usr/bin/env bash
# backup.sh - dump the Postgres database to a compressed, timestamped file.
#   ./scripts/backup.sh [compose|k8s]     (default compose)
# Keeps the newest KEEP backups (default 7) and deletes older ones.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-compose}"; KEEP="${KEEP:-7}"
DEST="$ROOT/backups"; mkdir -p "$DEST"
FILE="$DEST/shop-$(date +%Y%m%d-%H%M%S).sql.gz"

case "$MODE" in
  compose) docker compose -f "$ROOT/docker/docker-compose.yml" exec -T db pg_dump -U shop shop | gzip > "$FILE" ;;
  k8s)     kubectl -n "${NAMESPACE:-shop}" exec deploy/shop-postgres -- pg_dump -U shop shop | gzip > "$FILE" ;;
  *) echo "usage: $0 {compose|k8s}"; exit 2 ;;
esac

[ -s "$FILE" ] || { echo "backup is empty - failing" >&2; rm -f "$FILE"; exit 1; }
echo "[backup] wrote $FILE ($(du -h "$FILE" | cut -f1))"

# retention: delete everything except the newest $KEEP
ls -1t "$DEST"/shop-*.sql.gz | tail -n +$((KEEP+1)) | xargs -r rm -v
