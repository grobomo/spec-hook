#!/usr/bin/env bash
# Set up a fresh Ubuntu instance for SHTD evidence testing.
# Run this ON the remote instance (via ssh or scp+execute).
# Usage: bash setup-evidence-instance.sh
set -euo pipefail

echo "=========================================="
echo "  SHTD Evidence Instance Setup"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Hostname: $(hostname)"
echo "  IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'unknown')"
echo "=========================================="

# --- Phase 1: System packages ---
echo ""
echo "=== Phase 1: Install system packages ==="
sudo apt-get update -qq
sudo apt-get install -y -qq git curl docker.io python3 python3-pip jq

# Node.js 20 via NodeSource
if ! command -v node >/dev/null 2>&1; then
  echo "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi
echo "Node: $(node --version)"
echo "Python: $(python3 --version)"
echo "Git: $(git --version)"
echo "Docker: $(docker --version)"

# --- Phase 2: Install Claude Code ---
echo ""
echo "=== Phase 2: Install Claude Code ==="
if ! command -v claude >/dev/null 2>&1; then
  sudo npm install -g @anthropic-ai/claude-code
fi
echo "Claude: $(claude --version 2>/dev/null || echo 'installed')"

# --- Phase 3: Install hook-runner + SHTD Flow ---
echo ""
echo "=== Phase 3: Install SHTD Flow (native) ==="
cd /tmp
rm -rf spec-hook
git clone --depth 1 https://github.com/grobomo/spec-hook.git
cd spec-hook
bash install.sh
echo ""
echo "=== Verify installation ==="
bash install.sh --check

# --- Phase 4: Docker setup ---
echo ""
echo "=== Phase 4: Docker setup ==="
sudo usermod -aG docker ubuntu 2>/dev/null || true
sudo systemctl start docker
sudo systemctl enable docker

# Pull a minimal container image
sudo docker pull ubuntu:22.04

# Create a CCC-like container with Node.js
echo "Building evidence test container..."
sudo docker run -d --name shtd-evidence-container \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-not-set}" \
  ubuntu:22.04 sleep infinity

# Install deps inside container
sudo docker exec shtd-evidence-container bash -c '
apt-get update -qq && apt-get install -y -qq git curl python3 jq
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs
npm install -g @anthropic-ai/claude-code
'

# Install SHTD inside container
sudo docker exec shtd-evidence-container bash -c '
cd /tmp
git clone --depth 1 https://github.com/grobomo/spec-hook.git
cd spec-hook
bash install.sh
echo "=== Container SHTD verify ==="
bash install.sh --check
'

echo ""
echo "=========================================="
echo "  Setup complete: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Native: Claude + SHTD installed"
echo "  Docker: shtd-evidence-container running with SHTD"
echo "=========================================="
