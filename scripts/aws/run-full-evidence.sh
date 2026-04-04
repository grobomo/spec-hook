#!/usr/bin/env bash
# Full evidence pipeline: provision EC2, setup, run evidence, render screenshots, generate PDF.
# Usage: bash scripts/aws/run-full-evidence.sh
#
# If instance already provisioned (instance-ip.txt exists), skips provisioning.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
KEY="$HOME/.ssh/ccc-keys/worker-5.pem"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15"

cd "$PROJECT_DIR"

# --- Step 1: Get or create instance ---
if [ -f instance-ip.txt ] && [ -s instance-ip.txt ]; then
  IP=$(cat instance-ip.txt)
  echo "=== Using existing instance: $IP ==="
else
  echo "=== Provisioning fresh instance ==="
  bash scripts/aws/provision-evidence-instance.sh
  IP=$(cat instance-ip.txt)
fi

echo "IP: $IP"

# --- Step 2: Upload scripts ---
echo ""
echo "=== Uploading scripts to instance ==="
TARBALL=$(mktemp /tmp/shtd-evidence-XXXXXX.tar.gz)
tar czf "$TARBALL" \
  scripts/setup-evidence-instance.sh \
  scripts/run-evidence-session.sh \
  scripts/render-terminal-screenshot.py

scp $SSH_OPTS -i "$KEY" "$TARBALL" ubuntu@"$IP":/tmp/shtd-evidence.tar.gz
ssh $SSH_OPTS -i "$KEY" ubuntu@"$IP" "mkdir -p /tmp/shtd-scripts && cd /tmp/shtd-scripts && tar xzf /tmp/shtd-evidence.tar.gz"
rm -f "$TARBALL"
echo "Scripts uploaded."

# --- Step 3: Run setup ---
echo ""
echo "=== Setting up instance (Node, Python, Claude, SHTD, Docker) ==="
ssh $SSH_OPTS -i "$KEY" ubuntu@"$IP" "bash /tmp/shtd-scripts/scripts/setup-evidence-instance.sh" 2>&1 | tee reports/setup-output.txt

# --- Step 4: Run evidence session (native) ---
echo ""
echo "=== Running evidence session (native mode) ==="
ssh $SSH_OPTS -i "$KEY" ubuntu@"$IP" "bash /tmp/shtd-scripts/scripts/run-evidence-session.sh" 2>&1 | tee reports/evidence-native-output.txt

# --- Step 5: Run evidence session (Docker) ---
echo ""
echo "=== Running evidence session (Docker mode) ==="
ssh $SSH_OPTS -i "$KEY" ubuntu@"$IP" "sudo docker exec shtd-evidence-container bash /tmp/shtd-scripts/scripts/run-evidence-session.sh --docker" 2>&1 | tee reports/evidence-docker-output.txt

# --- Step 6: Download evidence captures ---
echo ""
echo "=== Downloading evidence captures ==="
mkdir -p reports/evidence-native reports/evidence-docker

# Native captures
scp $SSH_OPTS -i "$KEY" ubuntu@"$IP":/tmp/shtd-evidence/native/*.txt reports/evidence-native/ 2>/dev/null || echo "No native captures found"

# Docker captures
ssh $SSH_OPTS -i "$KEY" ubuntu@"$IP" "sudo docker cp shtd-evidence-container:/tmp/shtd-evidence/docker/ /tmp/shtd-evidence-docker/" 2>/dev/null || true
scp $SSH_OPTS -i "$KEY" ubuntu@"$IP":/tmp/shtd-evidence-docker/*.txt reports/evidence-docker/ 2>/dev/null || echo "No docker captures found"

echo "Downloaded evidence captures."

# --- Step 7: Render terminal screenshots ---
echo ""
echo "=== Rendering terminal screenshots ==="
python3 scripts/render-terminal-screenshot.py reports/evidence-native reports/screenshots/native
python3 scripts/render-terminal-screenshot.py reports/evidence-docker reports/screenshots/docker

# --- Step 8: Generate PDF report ---
echo ""
echo "=== Generating PDF report ==="
python3 scripts/generate-evidence-report.py

echo ""
echo "=========================================="
echo "  Evidence pipeline complete"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
ls -la reports/*.pdf 2>/dev/null
