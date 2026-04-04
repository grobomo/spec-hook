#!/usr/bin/env bash
# Test: enforce-shtd meta-workflow blocks out-of-order steps
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
SETUP="$HR_DIR/setup.js"

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

errors=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Copy enforce-shtd to the project so it's discoverable
mkdir -p "$TMPDIR/workflows"
cp "$HR_DIR/workflows/enforce-shtd.yml" "$TMPDIR/workflows/"

WF_JS=$(to_node "$HR_DIR/workflow.js")
GATE_JS=$(to_node "$HR_DIR/modules/PreToolUse/workflow-gate.js")
TP=$(to_node "$TMPDIR")

# === Test 1: Start enforce-shtd workflow ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow start enforce-shtd 2>&1)
if echo "$OUTPUT" | grep -q "Started.*spec"; then
  echo "[OK] enforce-shtd starts at 'spec' step"
else
  echo "[FAIL] start: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 2: Gate blocks code edits (spec step has no file requirement, but tasks step requires spec) ===
# Complete spec step first
mkdir -p "$TMPDIR/specs/001-test"
echo "# Spec" > "$TMPDIR/specs/001-test/spec.md"
cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete spec >/dev/null 2>&1

# Now on tasks step — try to skip to implement
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  delete require.cache[require.resolve('$WF_JS')];
  delete require.cache[require.resolve('$GATE_JS')];
  var wf = require('$WF_JS');
  // Check gate for 'implement' step directly — should be blocked
  var check = wf.checkGate('implement', '$TP');
  console.log(check.allowed ? 'allowed' : 'blocked');
")
if [ "$RESULT" = "blocked" ]; then
  echo "[OK] Cannot skip to 'implement' — must complete 'tasks' first"
else
  echo "[FAIL] expected blocked, got: $RESULT"
  errors=$((errors + 1))
fi

# === Test 3: Complete tasks, workflow, branch — then implement is reachable ===
echo "# Tasks" > "$TMPDIR/specs/001-test/tasks.md"
cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete tasks >/dev/null 2>&1

echo "# WF" > "$TMPDIR/workflows/test.yml"
cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete workflow >/dev/null 2>&1
cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete branch >/dev/null 2>&1
cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow complete test >/dev/null 2>&1

# Now on 'implement' — gate should allow
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  delete require.cache[require.resolve('$WF_JS')];
  delete require.cache[require.resolve('$GATE_JS')];
  var gate = require('$GATE_JS');
  var r = gate({tool_name:'Write', tool_input:{file_path:'$TP/src/main.js'}});
  console.log(r === null ? 'allowed' : 'blocked');
")
if [ "$RESULT" = "allowed" ]; then
  echo "[OK] Gate allows edits at 'implement' step after prerequisites met"
else
  echo "[FAIL] expected allowed at implement, got: $RESULT"
  errors=$((errors + 1))
fi

# === Test 4: Status shows progress ===
OUTPUT=$(cd "$TMPDIR" && CLAUDE_PROJECT_DIR="$TMPDIR" node "$SETUP" --workflow status 2>&1)
if echo "$OUTPUT" | grep -q "enforce-shtd" && echo "$OUTPUT" | grep -q "OK.*spec.*completed"; then
  echo "[OK] Status shows enforce-shtd progress"
else
  echo "[FAIL] status: $OUTPUT"
  errors=$((errors + 1))
fi

# === Test 5: The meta-workflow enforces its own pattern (self-referential) ===
# Starting enforce-shtd in a fresh project should block code until spec exists
TMPDIR2=$(mktemp -d)
mkdir -p "$TMPDIR2/workflows"
cp "$HR_DIR/workflows/enforce-shtd.yml" "$TMPDIR2/workflows/"
TP2=$(to_node "$TMPDIR2")

cd "$TMPDIR2" && CLAUDE_PROJECT_DIR="$TMPDIR2" node "$SETUP" --workflow start enforce-shtd >/dev/null 2>&1

# The gate module won't block because spec step has require_files: [] (empty gate)
# But the WORKFLOW is active, which means the workflow-gate is engaged
# After completing spec, tasks step requires specs/*/tasks.md
RESULT=$(node -e "
  process.env.CLAUDE_PROJECT_DIR = '$TP2';
  delete require.cache[require.resolve('$WF_JS')];
  delete require.cache[require.resolve('$GATE_JS')];
  var wf = require('$WF_JS');
  // Skip spec, try tasks — it requires spec to be completed
  var check = wf.checkGate('tasks', '$TP2');
  console.log(check.allowed ? 'allowed' : 'blocked');
")
if [ "$RESULT" = "blocked" ]; then
  echo "[OK] Meta: enforce-shtd blocks tasks step until spec is done"
else
  echo "[FAIL] meta test expected blocked, got: $RESULT"
  errors=$((errors + 1))
fi

rm -rf "$TMPDIR2"

echo ""
echo "=== $((5 - errors))/5 enforce-shtd tests passed ==="
exit $errors
