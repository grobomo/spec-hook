#!/usr/bin/env bash
# Deploy SHTD Flow to all CCC workers (1-4).
# Usage: bash scripts/deploy-to-all-workers.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for w in 1 2 3 4; do
  echo ""
  echo "========================================="
  echo "  Deploying to Worker $w"
  echo "========================================="
  bash "$SCRIPT_DIR/deploy-to-worker.sh" "$w" 2>&1 || echo "[WARN] Worker $w failed"
  echo ""
done

echo "========================================="
echo "  Deployment complete — verifying all"
echo "========================================="

for w in 1 2 3 4; do
  echo ""
  echo "--- Worker $w ---"
  bash "$SCRIPT_DIR/check-worker-install.sh" "$w" 2>&1 | grep -E "\[OK\]|\[FAIL\]|not found|error" | head -5
done

echo ""
echo "Done."
