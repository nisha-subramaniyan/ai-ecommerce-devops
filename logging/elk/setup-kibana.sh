#!/usr/bin/env bash
# Create the Kibana "data view" (index pattern) for our logs so Discover works immediately.
set -euo pipefail
KIBANA="${KIBANA:-http://localhost:5601}"
echo "Waiting for Kibana..."
until curl -fs "$KIBANA/api/status" >/dev/null; do sleep 5; done
curl -fsS -X POST "$KIBANA/api/data_views/data_view" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"data_view":{"title":"shop-logs-*","name":"Shop logs","timeFieldName":"@timestamp"}}' \
  && echo && echo "Data view created. Open $KIBANA/app/discover"
