#!/usr/bin/env bash
# E2E test: full workflow lifecycle in hook-runner (engine + gate + CLI)
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
SETUP="$HR_DIR/setup.js"

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

errors=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Set up a fake project with a workflow
mkdir -p "$TMPDIR/workflows" "$TMPDIR/specs/001-test/scripts/test"

cat > "$TMPDIR/workflows/e2e-test.yml" <<'YAML'
name: e2e-test
description: End-to-end test workflow
version: 1
steps:
  - id: plan
    name: Write plan
    gate:
      require_files: []
    completion:
      require_files: ["plan.md"]
  - id: build
    name: Build feature
    gate:
      require_step: plan
      require_files: ["plan.md"]
    completion:
      require_files: ["output.txt"]
  - id: verify
    name: Run verification
    gate:
      require_step: build
    completion:
      require_files: ["verified.txt"]
YAML

TP=$(to_node "$TMPDIR")
WF_JS=$(to_node "$HR_DIR/workflow.js")
GATE_JS=$(to_node "$HR_DIR/modules/PreToolUse/workflow-gate.js")

# === Test 1: CLI list discovers the workflow ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow list 2>&1)
if echo "$OUTPUT" | grep -q "e2e-test"; then
  echo "[OK] CLI list discovers e2e-test workflow"
else
  echo "[FAIL] CLI list: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 2: CLI start activates workflow ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow start e2e-test 2>&1)
if echo "$OUTPUT" | grep -q "Started.*plan"; then
  echo "[OK] CLI start activates workflow at step 'plan'"
else
  echo "[FAIL] CLI start: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 3: Gate blocks when require_files missing for step 'build' ===
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  delete require.cache[require.resolve('$GATE_JS')];
  delete require.cache[require.resolve('$WF_JS')];
  var wf = require('$WF_JS');
  // Manually advance to build step (plan not completed yet)
  var state = wf.readState('$TP');
  // Try to check gate for build — plan not completed
  var check = wf.checkGate('build', '$TP');
  console.log(check.allowed ? 'allowed' : 'blocked');
")
if [ "$RESULT" = "blocked" ]; then
  echo "[OK] Gate blocks step 'build' when 'plan' not completed"
else
  echo "[FAIL] expected blocked, got: $RESULT"
  errors=$((errors + 1))
fi

# === Test 4: Create plan.md, complete step, gate passes ===
echo "# Plan" > "$TMPDIR/plan.md"
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete plan 2>&1)
if echo "$OUTPUT" | grep -q "Completed.*plan"; then
  echo "[OK] CLI complete advances past 'plan'"
else
  echo "[FAIL] CLI complete: $OUTPUT"
  errors=$((errors + 1))
fi

# Now gate should allow edits (build step's gate: require_step plan + require_files plan.md)
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  delete require.cache[require.resolve('$GATE_JS')];
  delete require.cache[require.resolve('$WF_JS')];
  var gate = require('$GATE_JS');
  var r = gate({tool_name:'Write', tool_input:{file_path:'$TP/src/main.js'}});
  console.log(r === null ? 'allowed' : 'blocked');
")
if [ "$RESULT" = "allowed" ]; then
  echo "[OK] Gate allows edits after 'plan' completed"
else
  echo "[FAIL] expected allowed, got: $RESULT"
  errors=$((errors + 1))
fi

# === Test 5: Status shows correct state ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow status 2>&1)
if echo "$OUTPUT" | grep -q "OK.*plan.*completed" && echo "$OUTPUT" | grep -q ">>.*build.*in_progress"; then
  echo "[OK] Status shows plan=completed, build=in_progress"
else
  echo "[FAIL] Status output: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 6: Complete remaining steps ===
echo "done" > "$TMPDIR/output.txt"
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete build 2>&1)
echo "verified" > "$TMPDIR/verified.txt"
OUTPUT2=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete verify 2>&1)
if echo "$OUTPUT2" | grep -q "complete\|Complete"; then
  echo "[OK] All steps completed"
else
  echo "[FAIL] final complete: $OUTPUT2"
  errors=$((errors + 1))
fi

# === Test 7: Reset clears state ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow reset 2>&1)
if echo "$OUTPUT" | grep -q "cleared\|Cleared"; then
  echo "[OK] Reset clears workflow state"
else
  echo "[FAIL] reset: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 8: After reset, no active workflow ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow status 2>&1)
if echo "$OUTPUT" | grep -q "No active"; then
  echo "[OK] No active workflow after reset"
else
  echo "[FAIL] post-reset status: $OUTPUT"
  errors=$((errors + 1))
fi

echo ""
echo "=== $((9 - errors))/9 e2e tests passed ==="
exit $errors
