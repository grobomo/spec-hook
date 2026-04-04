#!/usr/bin/env bash
# Shared worker configuration — single source of truth for CCC worker IPs and SSH settings.
# Source this from any worker script: source "$(dirname "$0")/worker-config.sh"

KEY_DIR="${HOME}/.ssh/ccc-keys"

declare -A WORKER_IPS=(
  [1]="18.219.224.145"
  [2]="18.223.188.176"
  [3]="3.143.229.17"
  [4]="52.14.228.211"
)

ALL_WORKERS="1 2 3 4"

ssh_opts_for() {
  local w="$1"
  echo "-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${KEY_DIR}/worker-${w}.pem"
}

resolve_worker() {
  local w="$1"
  local ip="${WORKER_IPS[$w]:-}"
  if [ -z "$ip" ]; then
    echo "Unknown worker: $w" >&2
    return 1
  fi
  echo "$ip"
}
