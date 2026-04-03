#!/usr/bin/env bash
# Test: lib/workflow.js — YAML parsing, state management, step validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Convert Git Bash paths to Windows paths (forward-slash) for Node.js require()
to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
NP=$(to_node "$PROJECT_DIR")
WORKFLOW_JS="${NP}/lib/workflow.js"
TMPDIR=$(mktemp -d)
NT=$(to_node "$TMPDIR")
ERRORS=0

fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }
pass() { echo "PASS: $1"; }

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Create a test workflow YAML
mkdir -p "$TMPDIR/workflows"
cat > "$TMPDIR/workflows/test-wf.yml" << 'EOF'
name: test-wf
description: Test workflow
version: 1
steps:
  - id: step1
    name: First step
    gate:
      require_files: []
    completion:
      require_files: ["step1-done.txt"]
  - id: step2
    name: Second step
    gate:
      require_step: step1
    completion:
      require_files: ["step2-done.txt"]
  - id: step3
    name: Third step
    gate:
      require_step: step2
      require_files: ["step2-done.txt"]
    completion:
      audit_event: step3_done
EOF

WF_YML="${NT}/workflows/test-wf.yml"

# --- Test 1: Load workflow ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  const def = wf.loadWorkflow('${WF_YML}');
  console.log(JSON.stringify({name: def.name, steps: def.steps.length}));
")
echo "$RESULT" | grep -q '"name":"test-wf"' && pass "Load workflow YAML" || fail "Load workflow YAML: $RESULT"
echo "$RESULT" | grep -q '"steps":3' && pass "Step count" || fail "Step count: $RESULT"

# --- Test 2: Init state ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  const state = wf.initState('test-wf', '${WF_YML}', '${NT}');
  console.log(JSON.stringify(state));
")
echo "$RESULT" | grep -q '"workflow":"test-wf"' && pass "Init state" || fail "Init state: $RESULT"
echo "$RESULT" | grep -q '"status":"pending"' && pass "Steps start pending" || fail "Steps not pending: $RESULT"

# --- Test 3: Check gates — step1 should be allowed (no prereqs) ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  const check = wf.checkGate('step1', '${NT}');
  console.log(JSON.stringify(check));
")
echo "$RESULT" | grep -q '"allowed":true' && pass "Step1 gate open" || fail "Step1 gate: $RESULT"

# --- Test 4: Check gates — step2 should be blocked (step1 not done) ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  const check = wf.checkGate('step2', '${NT}');
  console.log(JSON.stringify(check));
")
echo "$RESULT" | grep -q '"allowed":false' && pass "Step2 blocked before step1" || fail "Step2 not blocked: $RESULT"

# --- Test 5: Complete step1, then step2 gate opens ---
touch "$TMPDIR/step1-done.txt"
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  wf.completeStep('step1', '${NT}');
  const check = wf.checkGate('step2', '${NT}');
  console.log(JSON.stringify(check));
")
echo "$RESULT" | grep -q '"allowed":true' && pass "Step2 opens after step1 complete" || fail "Step2 still blocked: $RESULT"

# --- Test 6: Step3 needs both require_step AND require_files ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  wf.completeStep('step1', '${NT}');
  // step2 not completed yet
  const check = wf.checkGate('step3', '${NT}');
  console.log(JSON.stringify(check));
")
echo "$RESULT" | grep -q '"allowed":false' && pass "Step3 blocked without step2" || fail "Step3 not blocked: $RESULT"

# --- Test 7: Complete step2, create file, step3 opens ---
touch "$TMPDIR/step2-done.txt"
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  wf.completeStep('step1', '${NT}');
  wf.completeStep('step2', '${NT}');
  const check = wf.checkGate('step3', '${NT}');
  console.log(JSON.stringify(check));
")
echo "$RESULT" | grep -q '"allowed":true' && pass "Step3 opens after step2+file" || fail "Step3 still blocked: $RESULT"

# --- Test 8: Get current step ---
RESULT=$(node -e "
  const wf = require('${WORKFLOW_JS}');
  wf.initState('test-wf', '${WF_YML}', '${NT}');
  console.log(JSON.stringify({current: wf.currentStep('${NT}')}));
")
echo "$RESULT" | grep -q '"current":"step1"' && pass "Current step is step1" || fail "Current step: $RESULT"

# --- Summary ---
echo ""
if [ $ERRORS -eq 0 ]; then
  echo "All tests passed."
  exit 0
else
  echo "$ERRORS test(s) failed."
  exit 1
fi
