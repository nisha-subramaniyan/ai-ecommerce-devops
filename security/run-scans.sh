#!/usr/bin/env bash
# run-scans.sh - run every DevSecOps check locally (the same ones Jenkins and GitHub Actions run).
#   ./security/run-scans.sh [image-tag]
# Exit code is non-zero if any BLOCKING check fails.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-local}"
FAIL=0
step() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
run()  { "$@" || FAIL=1; }

step "1/5 Secret detection (gitleaks) - blocking"
if command -v gitleaks >/dev/null; then run gitleaks detect --source "$ROOT" --no-banner --redact; else echo "gitleaks not installed (run scripts/setup.sh)"; FAIL=1; fi

step "2/5 Dependency vulnerabilities (npm audit, high+) - blocking"
( cd "$ROOT/application/backend" && run npm audit --omit=dev --audit-level=high )

step "3/5 Filesystem + dependency scan (trivy fs, HIGH/CRITICAL) - informational"
command -v trivy >/dev/null && trivy fs --severity HIGH,CRITICAL --no-progress "$ROOT/application" || echo "trivy not installed"

step "4/5 Kubernetes / Helm / Dockerfile misconfiguration (trivy config) - informational"
command -v trivy >/dev/null && trivy config --severity HIGH,CRITICAL "$ROOT/kubernetes" "$ROOT/helm" "$ROOT/docker" || true

step "5/5 Container image scan (trivy image, CRITICAL) - blocking"
if command -v trivy >/dev/null && docker image inspect "shop-backend:$TAG" >/dev/null 2>&1; then
  run trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 --no-progress "shop-backend:$TAG"
else
  echo "skipped: build an image first (docker build -f docker/Dockerfile -t shop-backend:$TAG .)"
fi

echo; [ $FAIL -eq 0 ] && echo "All blocking security checks passed." || echo "Security checks FAILED."
exit $FAIL
