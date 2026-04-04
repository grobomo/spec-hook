#!/usr/bin/env bash
# Check what's actually installed on a CCC worker for SHTD flow.
# Usage: bash scripts/check-worker-install.sh [worker_num]

set -euo pipefail

WORKER="${1:-1}"
KEY_DIR="$HOME/.ssh/ccc-keys"

declare -A IPS=([1]="18.219.224.145" [2]="18.223.188.176" [3]="3.143.229.17" [4]="52.14.228.211")
IP="${IPS[$WORKER]:-}"
[ -z "$IP" ] && echo "Unknown worker: $WORKER" && exit 1
KEY="$KEY_DIR/worker-${WORKER}.pem"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY"

echo "=== Worker $WORKER ($IP) — Installation Check ==="
echo ""

ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EOF'
echo "--- Host level ---"
echo "Hostname: $(hostname)"
echo "Docker: $(docker --version 2>/dev/null || echo 'not installed')"
echo ""

echo "--- Container: claude-portable ---"
docker exec claude-portable bash -c '
echo "Node: $(node --version 2>/dev/null || echo missing)"
echo "Claude: $(which claude 2>/dev/null || echo missing)"
echo ""

echo "--- ~/.claude/ structure ---"
ls -la $HOME/.claude/ 2>/dev/null || echo "$HOME/.claude/ not found"
echo ""

echo "--- ~/.claude/hooks/ ---"
find $HOME/.claude/hooks/ -type f 2>/dev/null | head -30 || echo "No hooks dir"
echo ""

echo "--- ~/.claude/shtd-flow/ ---"
ls -la $HOME/.claude/shtd-flow/ 2>/dev/null || echo "shtd-flow dir not found"
echo ""

echo "--- ~/.claude/shtd-flow/lib/ ---"
ls -la $HOME/.claude/shtd-flow/lib/ 2>/dev/null || echo "lib dir not found"
echo ""

echo "--- ~/.claude/shtd-flow/hooks/ ---"
find $HOME/.claude/shtd-flow/hooks/ -type f 2>/dev/null | head -30 || echo "No shtd-flow hooks"
echo ""

echo "--- Hook runner (run-pretooluse.js, run-posttooluse.js, run-stop.js) ---"
for f in run-pretooluse.js run-posttooluse.js run-stop.js; do
  found=$(find $HOME/.claude/ -name "$f" 2>/dev/null | head -3)
  echo "$f: ${found:-NOT FOUND}"
done
echo ""

echo "--- settings.json hook config ---"
cat $HOME/.claude/settings.json 2>/dev/null | python3 -m json.tool 2>/dev/null || cat $HOME/.claude/settings.json 2>/dev/null || echo "No settings.json"
echo ""

echo "--- install.sh permissions ---"
ls -la $HOME/.claude/shtd-flow/install.sh 2>/dev/null || echo "install.sh not found"
' 2>&1
EOF
