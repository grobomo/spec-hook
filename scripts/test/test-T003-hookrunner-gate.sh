#!/usr/bin/env bash
# Test: workflow-gate PreToolUse module exists in hook-runner and works
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

errors=0

# Module exists
if [ -f "$HR_DIR/modules/PreToolUse/workflow-gate.js" ]; then
  echo "[OK] workflow-gate.js exists"
else
  echo "[FAIL] modules/PreToolUse/workflow-gate.js missing"
  exit 1
fi

MOD_JS=$(to_node "$HR_DIR/modules/PreToolUse/workflow-gate.js")

# Module loads
if node -e "require('$MOD_JS')" 2>/dev/null; then
  echo "[OK] module loads without error"
else
  echo "[FAIL] module fails to load"
  errors=$((errors + 1))
fi

# Module exports a function
TYPEOF=$(node -e "console.log(typeof require('$MOD_JS'))")
if [ "$TYPEOF" = "function" ]; then
  echo "[OK] exports a function"
else
  echo "[FAIL] expected function, got $TYPEOF"
  errors=$((errors + 1))
fi

# Returns null when no active workflow
RESULT=$(node -e "
  const gate = require('$MOD_JS');
  process.env.CLAUDE_PROJECT_DIR = require('os').tmpdir();
  const r = gate({tool_name:'Write', tool_input:{file_path:'/tmp/foo.js'}});
  console.log(r === null ? 'null' : JSON.stringify(r));
")
if [ "$RESULT" = "null" ]; then
  echo "[OK] returns null when no active workflow"
else
  echo "[FAIL] expected null, got: $RESULT"
  errors=$((errors + 1))
fi

# Returns null for allowed paths (TODO.md, specs/, etc.)
RESULT=$(node -e "
  const gate = require('$MOD_JS');
  process.env.CLAUDE_PROJECT_DIR = require('os').tmpdir();
  const r = gate({tool_name:'Write', tool_input:{file_path:'/tmp/project/TODO.md'}});
  console.log(r === null ? 'null' : JSON.stringify(r));
")
if [ "$RESULT" = "null" ]; then
  echo "[OK] allows TODO.md edits"
else
  echo "[FAIL] expected null for TODO.md, got: $RESULT"
  errors=$((errors + 1))
fi

# Blocks when gate unsatisfied
WF_JS=$(to_node "$HR_DIR/workflow.js")
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
TP=$(to_node "$TMPDIR")

cat > "$TMPDIR/test.yml" <<'YAML'
name: gate-test
steps:
  - id: step1
    name: First
    gate:
      require_files: ["nonexistent.txt"]
    completion:
      require_files: []
YAML

TY=$(to_node "$TMPDIR/test.yml")

RESULT=$(node -e "
  const wf = require('$WF_JS');
  wf.initState('gate-test', '$TY', '$TP');
  const gate = require('$MOD_JS');
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  const r = gate({tool_name:'Write', tool_input:{file_path:'$TP/src/main.js'}});
  console.log(r && r.decision === 'block' ? 'blocked' : 'not-blocked');
")
if [ "$RESULT" = "blocked" ]; then
  echo "[OK] blocks when gate unsatisfied"
else
  echo "[FAIL] expected blocked, got: $RESULT"
  errors=$((errors + 1))
fi

# Passes when gate satisfied
RESULT=$(node -e "
  const wf = require('$WF_JS');
  const fs = require('fs');
  // Reset and use a workflow with no gate requirements
  fs.unlinkSync('$TP/.workflow-state.json');
  fs.writeFileSync('$TP/test2.yml', \`name: pass-test
steps:
  - id: step1
    name: First
    gate:
      require_files: []
    completion:
      require_files: []
\`);
  wf.initState('pass-test', '$TP/test2.yml', '$TP');
  const gate = require('$MOD_JS');
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  // Clear require cache to get fresh module
  delete require.cache[require.resolve('$MOD_JS')];
  const gate2 = require('$MOD_JS');
  const r = gate2({tool_name:'Write', tool_input:{file_path:'$TP/src/main.js'}});
  console.log(r === null ? 'passed' : JSON.stringify(r));
")
if [ "$RESULT" = "passed" ]; then
  echo "[OK] passes when gate satisfied"
else
  echo "[FAIL] expected passed, got: $RESULT"
  errors=$((errors + 1))
fi

# Only triggers on Write/Edit
RESULT=$(node -e "
  delete require.cache[require.resolve('$MOD_JS')];
  const gate = require('$MOD_JS');
  process.env.CLAUDE_PROJECT_DIR = '$TP';
  const r = gate({tool_name:'Bash', tool_input:{command:'echo hi'}});
  console.log(r === null ? 'skipped' : 'triggered');
")
if [ "$RESULT" = "skipped" ]; then
  echo "[OK] skips non-Write/Edit tools"
else
  echo "[FAIL] expected skipped, got: $RESULT"
  errors=$((errors + 1))
fi

echo ""
echo "=== $((8 - errors))/8 tests passed ==="
exit $errors
