#!/usr/bin/env bash
# Test: scripts/shtd-workflow.sh — CLI for workflow management
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="${PROJECT_DIR}/scripts/shtd-workflow.sh"
TMPDIR=$(mktemp -d)
ERRORS=0

fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }
pass() { echo "PASS: $1"; }

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Create a test workflow
mkdir -p "$TMPDIR/workflows"
cat > "$TMPDIR/workflows/test-cli.yml" << 'EOF'
name: test-cli
description: CLI test workflow
version: 1
steps:
  - id: first
    name: First step
    gate:
      require_files: []
    completion:
      require_files: ["first-done.txt"]
  - id: second
    name: Second step
    gate:
      require_step: first
    completion:
      require_files: ["second-done.txt"]
EOF

# --- Test 1: List workflows ---
RESULT=$(bash "$CLI" list "$TMPDIR" 2>&1)
echo "$RESULT" | grep -q "test-cli" && pass "List shows workflow" || fail "List: $RESULT"

# --- Test 2: Start workflow ---
RESULT=$(bash "$CLI" start test-cli "$TMPDIR" 2>&1)
echo "$RESULT" | grep -qi "started\|active\|first" && pass "Start workflow" || fail "Start: $RESULT"

# --- Test 3: Status shows current step ---
RESULT=$(bash "$CLI" status "$TMPDIR" 2>&1)
echo "$RESULT" | grep -q "first" && pass "Status shows first step" || fail "Status: $RESULT"

# --- Test 4: Complete step ---
touch "$TMPDIR/first-done.txt"
RESULT=$(bash "$CLI" complete first "$TMPDIR" 2>&1)
echo "$RESULT" | grep -qi "completed\|done\|second" && pass "Complete step" || fail "Complete: $RESULT"

# --- Test 5: Status after complete ---
RESULT=$(bash "$CLI" status "$TMPDIR" 2>&1)
echo "$RESULT" | grep -q "second" && pass "Status shows second step" || fail "Status after complete: $RESULT"

# --- Test 6: Reset ---
RESULT=$(bash "$CLI" reset "$TMPDIR" 2>&1)
echo "$RESULT" | grep -qi "reset\|cleared" && pass "Reset workflow" || fail "Reset: $RESULT"
[ ! -f "$TMPDIR/.shtd-workflow-state.json" ] && pass "State file removed" || fail "State file still exists"

# --- Summary ---
echo ""
if [ $ERRORS -eq 0 ]; then
  echo "All tests passed."
  exit 0
else
  echo "$ERRORS test(s) failed."
  exit 1
fi
