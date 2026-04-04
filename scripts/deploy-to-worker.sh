#!/usr/bin/env bash
# Deploy SHTD Flow to a CCC worker's Docker container.
# Copies source, runs install.sh inside the container.
#
# Usage: bash scripts/deploy-to-worker.sh [worker_num]  # default: 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKER="${1:-1}"

source "$SCRIPT_DIR/worker-config.sh"
IP=$(resolve_worker "$WORKER")
SSH_OPTS=$(ssh_opts_for "$WORKER")

echo "=== Deploying SHTD Flow to Worker $WORKER ($IP) ==="

# Create a tarball of the project (excluding .git, reports, node_modules)
TARBALL=$(mktemp /tmp/shtd-deploy-XXXXXX.tar.gz)
cd "$PROJECT_DIR"
tar czf "$TARBALL" \
  --exclude='.git' \
  --exclude='reports' \
  --exclude='node_modules' \
  --exclude='archive' \
  --exclude='SESSION_STATE.md' \
  lib/ hooks/ rules/ scripts/shtd-*.sh install.sh workflows/ 2>/dev/null || \
tar czf "$TARBALL" \
  --exclude='.git' \
  --exclude='reports' \
  --exclude='node_modules' \
  lib/ hooks/ rules/ install.sh 2>/dev/null

echo "Tarball: $(du -h "$TARBALL" | cut -f1)"

# Upload to host
scp $SSH_OPTS "$TARBALL" ubuntu@"$IP":/tmp/shtd-deploy.tar.gz

# Copy into container and install
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'DEPLOY'
set -e

# Copy tarball into container
docker cp /tmp/shtd-deploy.tar.gz claude-portable:/tmp/shtd-deploy.tar.gz

# Install inside container
docker exec claude-portable bash -c '
set -e
mkdir -p /tmp/shtd-install
cd /tmp/shtd-install
tar xzf /tmp/shtd-deploy.tar.gz

# Ensure install.sh is executable
chmod +x install.sh
chmod +x scripts/shtd-*.sh 2>/dev/null || true

# Set up git identity for tests (needed inside container)
git config --global user.email "claude@shtd-flow.test" 2>/dev/null || true
git config --global user.name "SHTD Test" 2>/dev/null || true

# Copy install.sh into deployed location (before install, in case verify exits non-zero)
mkdir -p $HOME/.claude/shtd-flow
cp install.sh $HOME/.claude/shtd-flow/install.sh

# Run installer (may exit non-zero from optional checks)
bash install.sh || true

# Cleanup
rm -rf /tmp/shtd-install /tmp/shtd-deploy.tar.gz
'

# Cleanup host
rm -f /tmp/shtd-deploy.tar.gz
echo ""
echo "=== Deployment complete ==="
DEPLOY

rm -f "$TARBALL"
