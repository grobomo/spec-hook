#!/usr/bin/env bash
# Verify SHTD installation on a CCC worker
# Usage: bash verify-worker.sh WORKER_NUM
set -euo pipefail

W="${1:?Usage: verify-worker.sh WORKER_NUM}"
KEY_DIR="${HOME}/.ssh/ccc-keys"

declare -A IPS=([1]="18.219.224.145" [2]="18.223.188.176" [3]="3.143.229.17" [4]="52.14.228.211")
IP="${IPS[$W]:-}"
[ -z "$IP" ] && echo "Unknown worker: $W" && exit 1

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${KEY_DIR}/worker-${W}.pem" \
  ubuntu@"$IP" "docker exec claude-portable bash -c 'bash /tmp/spec-hook/install.sh --check'" 2>&1
