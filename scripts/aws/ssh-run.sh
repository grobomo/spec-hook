#!/usr/bin/env bash
# Run a command on a remote EC2 instance via SSH
# Usage: bash ssh-run.sh IP KEY_PATH COMMAND...
set -euo pipefail
IP="${1:?Usage: ssh-run.sh IP KEY_PATH COMMAND...}"
KEY="${2:?Usage: ssh-run.sh IP KEY_PATH COMMAND...}"
shift 2
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" ubuntu@"$IP" "$@"
