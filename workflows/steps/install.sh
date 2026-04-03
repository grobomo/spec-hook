#!/usr/bin/env bash
# Workflow step: install — Install Claude Code + SHTD flow on remote instance
# Supports both container (docker exec) and native (direct SSH) modes.
#
# Requires: instance-id.txt, instance-ip.txt
# Produces: install-verified.txt

set -euo pipefail

PROJECT_DIR="${1:-.}"
IP=$(cat "${PROJECT_DIR}/instance-ip.txt")
NAME=$(cat "${PROJECT_DIR}/instance-name.txt" 2>/dev/null || echo "shtd-test")
SSH_KEY="${HOME}/.ssh/claude-portable.pem"

# Detect mode: container or native
# Container mode: claude-portable uses Docker
# Native mode: direct install on EC2 Ubuntu
MODE="${INSTALL_MODE:-container}"

echo "Installing on ${IP} (mode: ${MODE})..."

ssh_cmd() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" ubuntu@"$IP" "$@"
}

docker_exec() {
  ssh_cmd "docker exec claude-portable bash -c '$*'"
}

# Wait for instance to be ready
echo "Waiting for SSH..."
for i in $(seq 1 30); do
  if ssh_cmd "echo ok" >/dev/null 2>&1; then break; fi
  sleep 10
done

if [ "$MODE" = "container" ]; then
  # Wait for Docker container
  echo "Waiting for Docker container..."
  for i in $(seq 1 30); do
    STATUS=$(ssh_cmd "docker ps --filter name=claude-portable --format '{{.Status}}'" 2>/dev/null || echo "")
    if [[ "$STATUS" == Up* ]]; then break; fi
    sleep 10
  done

  # Install SHTD flow inside container
  echo "Installing SHTD flow in container..."
  docker_exec "cd /workspace && git clone https://github.com/grobomo/spec-hook.git /tmp/spec-hook"
  docker_exec "cd /tmp/spec-hook && bash install.sh"
  docker_exec "bash /tmp/spec-hook/install.sh --check"

else
  # Native mode: install directly
  echo "Installing SHTD flow natively..."
  ssh_cmd "git clone https://github.com/grobomo/spec-hook.git /tmp/spec-hook"

  # Install hook-runner first (prereq)
  ssh_cmd "git clone https://github.com/grobomo/hook-runner.git /tmp/hook-runner && cd /tmp/hook-runner && bash install.sh" || true

  ssh_cmd "cd /tmp/spec-hook && bash install.sh"
  ssh_cmd "bash /tmp/spec-hook/install.sh --check"
fi

echo "install-verified" > "${PROJECT_DIR}/install-verified.txt"
echo "SHTD flow installed successfully on ${IP}"
