#!/usr/bin/env bash
# Test: workflow.js exists in hook-runner and works correctly
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

errors=0

# workflow.js exists in hook-runner
if [ -f "$HR_DIR/workflow.js" ]; then
  echo "[OK] workflow.js exists in hook-runner"
else
  echo "[FAIL] workflow.js missing from hook-runner"
  exit 1
fi

WF_JS=$(to_node "$HR_DIR/workflow.js")

# Can load without error
if node -e "require('$WF_JS')" 2>/dev/null; then
  echo "[OK] workflow.js loads without error"
else
  echo "[FAIL] workflow.js fails to load"
  errors=$((errors + 1))
fi

# parseYaml works
RESULT=$(node -e "
  const wf = require('$WF_JS');
  const parsed = wf.parseYaml('name: test\nversion: 1\nsteps:\n  - id: s1\n    name: Step 1');
  console.log(JSON.stringify(parsed));
")
if echo "$RESULT" | grep -q '"name":"test"'; then
  echo "[OK] parseYaml works"
else
  echo "[FAIL] parseYaml returned: $RESULT"
  errors=$((errors + 1))
fi

# State management works
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Create a test workflow YAML
cat > "$TMPDIR/test.yml" <<'YAML'
name: test-wf
steps:
  - id: step1
    name: First
    gate:
      require_files: []
    completion:
      require_files: []
  - id: step2
    name: Second
    gate:
      require_step: step1
    completion:
      require_files: []
YAML

TP=$(to_node "$TMPDIR")
TY=$(to_node "$TMPDIR/test.yml")

# initState + currentStep
CURRENT=$(node -e "
  const wf = require('$WF_JS');
  wf.initState('test-wf', '$TY', '$TP');
  console.log(wf.currentStep('$TP'));
")
if [ "$CURRENT" = "step1" ]; then
  echo "[OK] initState + currentStep works"
else
  echo "[FAIL] expected step1, got: $CURRENT"
  errors=$((errors + 1))
fi

# completeStep + advance
NEXT=$(node -e "
  const wf = require('$WF_JS');
  wf.completeStep('step1', '$TP');
  console.log(wf.currentStep('$TP'));
")
if [ "$NEXT" = "step2" ]; then
  echo "[OK] completeStep advances correctly"
else
  echo "[FAIL] expected step2, got: $NEXT"
  errors=$((errors + 1))
fi

# checkGate blocks when prerequisite not met
GATE=$(node -e "
  const wf = require('$WF_JS');
  const tmpDir2 = require('os').tmpdir() + '/wf-test-' + Date.now();
  require('fs').mkdirSync(tmpDir2, {recursive:true});
  require('fs').writeFileSync(tmpDir2 + '/test.yml', \`name: gate-test
steps:
  - id: a
    name: A
    gate:
      require_files: []
    completion:
      require_files: []
  - id: b
    name: B
    gate:
      require_step: a
    completion:
      require_files: []
\`);
  const p = '$TP'.replace(/\\\\/g,'/');
  wf.initState('gate-test', tmpDir2.replace(/\\\\/g,'/') + '/test.yml', tmpDir2.replace(/\\\\/g,'/'));
  const check = wf.checkGate('b', tmpDir2.replace(/\\\\/g,'/'));
  console.log(check.allowed ? 'allowed' : 'blocked');
")
if [ "$GATE" = "blocked" ]; then
  echo "[OK] checkGate blocks when prerequisite not met"
else
  echo "[FAIL] expected blocked, got: $GATE"
  errors=$((errors + 1))
fi

# Exports all expected functions
EXPORTS=$(node -e "
  const wf = require('$WF_JS');
  const fns = ['parseYaml','loadWorkflow','findWorkflows','readState','writeState','initState','completeStep','currentStep','checkGate','checkEditAllowed'];
  const missing = fns.filter(f => typeof wf[f] !== 'function');
  console.log(missing.length === 0 ? 'all' : 'missing:' + missing.join(','));
")
if [ "$EXPORTS" = "all" ]; then
  echo "[OK] all expected functions exported"
else
  echo "[FAIL] $EXPORTS"
  errors=$((errors + 1))
fi

echo ""
echo "=== $((7 - errors))/7 tests passed ==="
exit $errors
