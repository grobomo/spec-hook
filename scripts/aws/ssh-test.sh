#!/usr/bin/env bash
# Test SSH connectivity to an EC2 instance
# Usage: bash ssh-test.sh IP [KEY_PATH]
set -euo pipefail
IP="${1:?Usage: ssh-test.sh IP [KEY_PATH]}"
KEY="${2:-${HOME}/.ssh/claude-portable-ec2.pem}"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$KEY" ubuntu@"$IP" "echo ok" 2>&1
