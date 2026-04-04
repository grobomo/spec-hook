#!/usr/bin/env bash
# Deploy SHTD Flow to CCC workers via SSH+Docker
# Usage: bash deploy-to-workers.sh [WORKER_NUMS...]
#   Default: deploys to workers 1-4
#   Example: bash deploy-to-workers.sh 1 3  (only workers 1 and 3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY_DIR="${HOME}/.ssh/ccc-keys"

# Worker IPs (from EC2 list)
declare -A WORKER_IPS=(
  [1]="18.219.224.145"
  [2]="18.223.188.176"
  [3]="3.143.229.17"
  [4]="52.14.228.211"
)

WORKERS="${@:-1 2 3 4}"
PASS=0; FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

for w in $WORKERS; do
  IP="${WORKER_IPS[$w]:-}"
  KEY="${KEY_DIR}/worker-${w}.pem"

  if [ -z "$IP" ]; then
    echo -e "${RED}[SKIP]${NC} Worker $w — no IP configured"
    ((FAIL++)) || true
    continue
  fi

  if [ ! -f "$KEY" ]; then
    echo -e "${RED}[SKIP]${NC} Worker $w — key not found: $KEY"
    ((FAIL++)) || true
    continue
  fi

  echo ""
  echo "=== Worker $w ($IP) ==="

  # Check connectivity
  if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY" ubuntu@"$IP" "echo ok" >/dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} Worker $w — SSH unreachable"
    ((FAIL++)) || true
    continue
  fi

  # Check Docker container
  if ! ssh -o StrictHostKeyChecking=no -i "$KEY" ubuntu@"$IP" "docker ps -q -f name=claude-portable" 2>/dev/null | grep -q .; then
    echo -e "${RED}[FAIL]${NC} Worker $w — claude-portable container not running"
    ((FAIL++)) || true
    continue
  fi

  # Clone and install inside container
  INSTALL_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "$KEY" ubuntu@"$IP" \
    "docker exec claude-portable bash -c 'rm -rf /tmp/spec-hook && git clone --depth 1 https://github.com/grobomo/spec-hook.git /tmp/spec-hook && bash /tmp/spec-hook/install.sh'" 2>&1) || true

  if echo "$INSTALL_OUTPUT" | grep -q "FAIL"; then
    echo -e "${RED}[FAIL]${NC} Worker $w — install had failures"
    echo "$INSTALL_OUTPUT" | tail -5
    ((FAIL++)) || true
    continue
  fi

  # Verify
  VERIFY_OUTPUT=$(ssh -o StrictHostKeyChecking=no -i "$KEY" ubuntu@"$IP" \
    "docker exec claude-portable bash -c 'bash /tmp/spec-hook/install.sh --check'" 2>&1) || true

  if echo "$VERIFY_OUTPUT" | grep -q "FAIL"; then
    echo -e "${RED}[FAIL]${NC} Worker $w — verification had failures"
    echo "$VERIFY_OUTPUT" | tail -5
    ((FAIL++)) || true
  else
    echo -e "${GREEN}[OK]${NC} Worker $w — SHTD installed and verified"
    ((PASS++)) || true
  fi
done

echo ""
echo "=== Deploy Summary ==="
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
