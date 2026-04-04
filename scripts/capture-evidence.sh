#!/usr/bin/env bash
# Capture real evidence from CCC workers showing SHTD hooks working.
# Runs real hook modules inside worker containers and captures output.
#
# Usage:
#   bash scripts/capture-evidence.sh [worker_num]  # default: 1
#
# Produces: reports/screenshots/evidence-capture-output.txt

set -uo pipefail
# NOT set -e — SSH commands may exit non-zero and we want to continue

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENSHOTS_DIR="$PROJECT_DIR/reports/screenshots"
KEY_DIR="$HOME/.ssh/ccc-keys"

WORKER="${1:-1}"

declare -A IPS=([1]="18.219.224.145" [2]="18.223.188.176" [3]="3.143.229.17" [4]="52.14.228.211")
IP="${IPS[$WORKER]:-}"
[ -z "$IP" ] && echo "Unknown worker: $WORKER" && exit 1
KEY="$KEY_DIR/worker-${WORKER}.pem"

mkdir -p "$SCREENSHOTS_DIR"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY"
CONTAINER="claude-portable"

snap() {
  python -c "
from PIL import ImageGrab
img = ImageGrab.grab()
img.save(r'$1')
print('Screenshot saved: $1 (' + str(img.size[0]) + 'x' + str(img.size[1]) + ')')
"
}

echo "============================================="
echo "  SHTD Evidence Capture — Worker $WORKER ($IP)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="
echo ""

# --- Evidence 1: install --check ---
echo "╔══════════════════════════════════════════╗"
echo "║  Evidence 1: SHTD Installation Verified  ║"
echo "╚══════════════════════════════════════════╝"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EV1'
echo "Worker: $(hostname) | $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "Docker:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo ""
# Run install check - $HOME resolves inside the container
docker exec claude-portable bash -c 'cd $HOME/.claude/shtd-flow && echo "=== install.sh --check ===" && bash install.sh --check 2>&1'
EV1
echo ""

# Helper: set up a git project with bare remote (so tracking works)
# This is how real projects work — each has a remote
echo "--- Setting up demo project with git remote ---"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'SETUP'
docker exec claude-portable bash -c '
rm -rf /tmp/demo-proj /tmp/demo-proj.git
git init -q --bare /tmp/demo-proj.git
git clone -q /tmp/demo-proj.git /tmp/demo-proj
cd /tmp/demo-proj
git config user.email "demo@shtd.test"
git config user.name "Demo"
git commit --allow-empty -m "init" -q
mkdir -p specs/001-feature
echo "# Feature spec" > specs/001-feature/spec.md
git add -A && git commit -q -m "add specs"
git push -q origin master
git checkout -q -b 001-add-feature
git push -q -u origin 001-add-feature
'
SETUP
echo ""

# --- Evidence 2: branch-gate BLOCKS on main ---
echo "╔══════════════════════════════════════════╗"
echo "║  Evidence 2: branch-gate BLOCKS on main  ║"
echo "╚══════════════════════════════════════════╝"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EV2'
docker exec claude-portable bash -c '
cd /tmp/demo-proj && git checkout -q master

echo "Project: /tmp/demo-proj"
echo "Branch: $(git branch --show-current)"
echo "specs/: EXISTS | Remote: $(git remote -v | head -1 | awk "{print \$2}")"
echo ""
echo ">>> Claude tries to Write src/app.js on master <<<"
echo ""

INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/demo-proj/src/app.js\",\"content\":\"hello\"}}"
cd /tmp/demo-proj
RESULT=$(echo "$INPUT" | node $HOME/.claude/hooks/run-pretooluse.js 2>&1) || true
echo "HOOK OUTPUT:"
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
echo ""
if echo "$RESULT" | grep -q "decision.*block"; then
  echo ">>> BLOCKED by branch-gate: cannot edit code on master"
else
  echo ">>> ALLOWED (unexpected)"
fi
'
EV2
echo ""

# --- Evidence 3: spec-gate BLOCKS without specs/ ---
echo "╔══════════════════════════════════════════╗"
echo "║  Evidence 3: spec-gate BLOCKS (no specs) ║"
echo "╚══════════════════════════════════════════╝"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EV3'
docker exec claude-portable bash -c '
# Second project: has remote+tracking but NO specs/
rm -rf /tmp/demo-bare /tmp/demo-bare.git
git init -q --bare /tmp/demo-bare.git
git clone -q /tmp/demo-bare.git /tmp/demo-bare
cd /tmp/demo-bare
git config user.email "demo@shtd.test"
git config user.name "Demo"
git commit --allow-empty -m "init" -q
git push -q origin master
git checkout -q -b 001-add-feature
git push -q -u origin 001-add-feature

echo "Project: /tmp/demo-bare"
echo "Branch: $(git branch --show-current)"
echo "specs/: $([ -d specs ] && echo EXISTS || echo MISSING)"
echo "Tracking: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo NONE)"
echo ""
echo ">>> Claude tries to Write src/app.js (no specs/) <<<"
echo ""

INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/demo-bare/src/app.js\",\"content\":\"hello\"}}"
cd /tmp/demo-bare
RESULT=$(echo "$INPUT" | node $HOME/.claude/hooks/run-pretooluse.js 2>&1) || true
echo "HOOK OUTPUT:"
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
echo ""
if echo "$RESULT" | grep -q "No specs"; then
  echo ">>> BLOCKED by spec-gate: must create specs/ before writing code"
else
  echo ">>> RESULT: $RESULT"
fi
rm -rf /tmp/demo-bare /tmp/demo-bare.git
'
EV3
echo ""

# --- Evidence 4: All gates PASS (proper setup) ---
echo "╔═══════════════════════════════════════════════╗"
echo "║  Evidence 4: All gates PASS (proper setup)     ║"
echo "╚═══════════════════════════════════════════════╝"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EV4'
docker exec claude-portable bash -c '
cd /tmp/demo-proj && git checkout -q 001-add-feature

echo "Project: /tmp/demo-proj"
echo "Branch: $(git branch --show-current)"
echo "specs/: EXISTS"
echo "Tracking: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo NONE)"
echo ""
echo ">>> Claude tries to Write src/app.js (all conditions met) <<<"
echo ""

INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/demo-proj/src/app.js\",\"content\":\"hello\"}}"
cd /tmp/demo-proj
RESULT=$(echo "$INPUT" | node $HOME/.claude/hooks/run-pretooluse.js 2>&1) || true
echo "HOOK OUTPUT: ${RESULT:-<empty — all gates passed>}"
echo ""
if [ -z "$RESULT" ]; then
  echo ">>> ALLOWED: feature branch + specs/ + remote tracking = all gates pass"
else
  echo ">>> BLOCKED (unexpected): $RESULT"
fi
'
EV4
echo ""

# --- Evidence 5: remote-tracking-gate BLOCKS untracked branch ---
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Evidence 5: remote-tracking-gate BLOCKS untracked   ║"
echo "╚══════════════════════════════════════════════════════╝"
ssh $SSH_OPTS ubuntu@"$IP" bash -s << 'EV5'
docker exec claude-portable bash -c '
cd /tmp/demo-proj
git checkout -q -b 002-untracked-branch 2>/dev/null || git checkout -q 002-untracked-branch

echo "Project: /tmp/demo-proj"
echo "Branch: $(git branch --show-current)"
echo "specs/: EXISTS"
echo "Tracking: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo NONE)"
echo ""
echo ">>> Claude tries to Write on untracked feature branch <<<"
echo ""

INPUT="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/demo-proj/src/app.js\",\"content\":\"hello\"}}"
cd /tmp/demo-proj
RESULT=$(echo "$INPUT" | node $HOME/.claude/hooks/run-pretooluse.js 2>&1) || true
echo "HOOK OUTPUT:"
echo "$RESULT" | python3 -m json.tool 2>/dev/null || echo "$RESULT"
echo ""
if echo "$RESULT" | grep -q "track a remote"; then
  echo ">>> BLOCKED by remote-tracking-gate: must push -u before editing"
else
  echo ">>> RESULT: $RESULT"
fi
'
EV5
echo ""

# --- Evidence 6: Local e2e test suite ---
echo "╔══════════════════════════════════════════╗"
echo "║  Evidence 6: E2E Test Suite (local)       ║"
echo "╚══════════════════════════════════════════╝"
cd "$PROJECT_DIR"
if [ -f scripts/test/test-T014-e2e-proof.sh ]; then
  bash scripts/test/test-T014-e2e-proof.sh 2>&1
else
  echo "Test script not found locally"
fi
echo ""

# --- Cleanup ---
ssh $SSH_OPTS ubuntu@"$IP" "docker exec $CONTAINER rm -rf /tmp/demo-proj" 2>/dev/null || true

echo "============================================="
echo "  Evidence capture complete"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="
