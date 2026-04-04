#!/usr/bin/env bash
# Final verification: all workflow components in place across both projects
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
SPEC_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

errors=0

# hook-runner has workflow.js
[ -f "$HR_DIR/workflow.js" ] && echo "[OK] hook-runner: workflow.js" || { echo "[FAIL] workflow.js"; errors=$((errors + 1)); }

# hook-runner has workflow-gate module
[ -f "$HR_DIR/modules/PreToolUse/workflow-gate.js" ] && echo "[OK] hook-runner: workflow-gate.js" || { echo "[FAIL] workflow-gate.js"; errors=$((errors + 1)); }

# hook-runner has built-in workflows
[ -f "$HR_DIR/workflows/enforce-shtd.yml" ] && echo "[OK] hook-runner: enforce-shtd.yml" || { echo "[FAIL] enforce-shtd.yml"; errors=$((errors + 1)); }
[ -f "$HR_DIR/workflows/cross-project-reset.yml" ] && echo "[OK] hook-runner: cross-project-reset.yml" || { echo "[FAIL] cross-project-reset.yml"; errors=$((errors + 1)); }

# hook-runner setup.js has --workflow command
grep -q "cmdWorkflow" "$HR_DIR/setup.js" && echo "[OK] hook-runner: --workflow in setup.js" || { echo "[FAIL] cmdWorkflow"; errors=$((errors + 1)); }

# spec-hook install still works
OUTPUT=$(cd "$SPEC_DIR" && bash install.sh --check 2>&1)
echo "$OUTPUT" | grep -q "installed successfully" && echo "[OK] spec-hook: install --check" || { echo "[FAIL] install --check"; errors=$((errors + 1)); }

# All spec-hook tests pass
for t in T001 T002 T003 T004 T005 T006 T007 T008; do
  SCRIPT=$(ls "$SPEC_DIR/scripts/test/test-${t}-"*.sh 2>/dev/null | head -1)
  if [ -n "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
    if bash "$SCRIPT" >/dev/null 2>&1; then
      echo "[OK] $t test passes"
    else
      echo "[FAIL] $t test failed"
      errors=$((errors + 1))
    fi
  fi
done

echo ""
echo "=== Final: $errors error(s) ==="
exit $errors
