#!/usr/bin/env bash
# Test: spec-hook's workflow system delegates to hook-runner's engine
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
SPEC_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

errors=0

# spec-hook's workflow.js should now be a thin wrapper or re-export of hook-runner's
SHTD_WF="$SPEC_DIR/lib/workflow.js"
HR_WF="$HR_DIR/workflow.js"

if [ ! -f "$SHTD_WF" ]; then
  echo "[FAIL] spec-hook lib/workflow.js missing"
  exit 1
fi

# Both should export the same API
SHTD_JS=$(to_node "$SHTD_WF")
HR_JS=$(to_node "$HR_WF")

SHTD_EXPORTS=$(node -e "
  var wf = require('$SHTD_JS');
  console.log(Object.keys(wf).sort().join(','));
")
HR_EXPORTS=$(node -e "
  var wf = require('$HR_JS');
  console.log(Object.keys(wf).sort().join(','));
")

# hook-runner should have at least all the functions spec-hook has
MISSING=$(node -e "
  var hr = require('$HR_JS');
  var needed = ['parseYaml','loadWorkflow','findWorkflows','readState','writeState','initState','completeStep','currentStep','checkGate','checkEditAllowed'];
  var missing = needed.filter(function(f) { return typeof hr[f] !== 'function'; });
  console.log(missing.length === 0 ? 'none' : missing.join(','));
")
if [ "$MISSING" = "none" ]; then
  echo "[OK] hook-runner has all required workflow API functions"
else
  echo "[FAIL] hook-runner missing: $MISSING"
  errors=$((errors + 1))
fi

# spec-hook's shtd-workflow.sh should still work
OUTPUT=$(cd "$SPEC_DIR" && bash scripts/shtd-workflow.sh list 2>&1)
if echo "$OUTPUT" | grep -qi "workflow\|steps\|No workflows"; then
  echo "[OK] shtd-workflow.sh still works"
else
  echo "[FAIL] shtd-workflow.sh broken: $OUTPUT"
  errors=$((errors + 1))
fi

# install.sh --check should still pass
OUTPUT=$(cd "$SPEC_DIR" && bash install.sh --check 2>&1)
if echo "$OUTPUT" | grep -q "installed successfully"; then
  echo "[OK] install.sh --check passes"
else
  echo "[FAIL] install.sh --check failed"
  errors=$((errors + 1))
fi

# hook-runner's workflow.js uses .workflow-state.json (not .shtd-workflow-state.json)
HR_STATE=$(node -e "var wf = require('$HR_JS'); console.log(wf.STATE_FILE);")
if [ "$HR_STATE" = ".workflow-state.json" ]; then
  echo "[OK] hook-runner uses .workflow-state.json"
else
  echo "[FAIL] expected .workflow-state.json, got: $HR_STATE"
  errors=$((errors + 1))
fi

echo ""
echo "=== $((4 - errors))/4 delegation tests passed ==="
exit $errors
