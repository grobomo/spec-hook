#!/usr/bin/env bash
# Test: hooks/PreToolUse/shtd_workflow-gate.js — enforces workflow step order
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
NP=$(to_node "$PROJECT_DIR")
GATE_JS="${NP}/hooks/PreToolUse/shtd_workflow-gate.js"
WORKFLOW_JS="${NP}/lib/workflow.js"
TMPDIR=$(mktemp -d)
NT=$(to_node "$TMPDIR")
ERRORS=0

fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }
pass() { echo "PASS: $1"; }

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Create a test workflow
mkdir -p "$TMPDIR/workflows"
cat > "$TMPDIR/workflows/test-gate.yml" << 'EOF'
name: test-gate
description: Test gate enforcement
version: 1
steps:
  - id: setup
    name: Setup
    gate:
      require_files: []
    completion:
      require_files: ["setup-done.txt"]
  - id: build
    name: Build
    gate:
      require_step: setup
    completion:
      require_files: ["build-done.txt"]
EOF

# Init workflow state
node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-gate', '${NT}/workflows/test-gate.yml', '${NT}');
"

# --- Test 1: Non-Write tools pass through ---
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '${NT}';
  const gate = require('${GATE_JS}');
  const r = gate({tool_name: 'Read', tool_input: {file_path: '${NT}/foo.js'}});
  console.log(JSON.stringify(r));
")
[ "$RESULT" = "null" ] && pass "Read tool not blocked" || fail "Read blocked: $RESULT"

# --- Test 2: Write on current step (setup) — allowed ---
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '${NT}';
  delete require.cache[require.resolve('${GATE_JS}')];
  const gate = require('${GATE_JS}');
  const r = gate({tool_name: 'Write', tool_input: {file_path: '${NT}/setup.js'}});
  console.log(JSON.stringify(r));
")
[ "$RESULT" = "null" ] && pass "Write allowed on current step" || fail "Write blocked on current step: $RESULT"

# --- Test 3: Allowed files (specs, tests, docs) always pass ---
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '${NT}';
  delete require.cache[require.resolve('${GATE_JS}')];
  const gate = require('${GATE_JS}');
  const r = gate({tool_name: 'Write', tool_input: {file_path: '${NT}/specs/001/spec.md'}});
  console.log(JSON.stringify(r));
")
[ "$RESULT" = "null" ] && pass "Spec file always allowed" || fail "Spec blocked: $RESULT"

# --- Test 4: After workflow completes, no blocking ---
node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.completeStep('setup', '${NT}');
  wf.completeStep('build', '${NT}');
"
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '${NT}';
  delete require.cache[require.resolve('${GATE_JS}')];
  const gate = require('${GATE_JS}');
  const r = gate({tool_name: 'Write', tool_input: {file_path: '${NT}/anything.js'}});
  console.log(JSON.stringify(r));
")
[ "$RESULT" = "null" ] && pass "No blocking after workflow complete" || fail "Blocked after complete: $RESULT"

# --- Summary ---
echo ""
if [ $ERRORS -eq 0 ]; then
  echo "All tests passed."
  exit 0
else
  echo "$ERRORS test(s) failed."
  exit 1
fi
