#!/usr/bin/env bash
# Test: built-in workflow templates exist in hook-runner
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
errors=0

# workflows/ directory exists
if [ -d "$HR_DIR/workflows" ]; then
  echo "[OK] workflows/ directory exists"
else
  echo "[FAIL] workflows/ directory missing"
  exit 1
fi

# enforce-shtd.yml exists and has required fields
if [ -f "$HR_DIR/workflows/enforce-shtd.yml" ]; then
  echo "[OK] enforce-shtd.yml exists"
  for field in "name:" "steps:" "gate:"; do
    if grep -q "$field" "$HR_DIR/workflows/enforce-shtd.yml"; then
      echo "[OK] enforce-shtd.yml has $field"
    else
      echo "[FAIL] enforce-shtd.yml missing $field"
      errors=$((errors + 1))
    fi
  done
else
  echo "[FAIL] workflows/enforce-shtd.yml missing"
  errors=$((errors + 1))
fi

# cross-project-reset.yml exists
if [ -f "$HR_DIR/workflows/cross-project-reset.yml" ]; then
  echo "[OK] cross-project-reset.yml exists"
else
  echo "[FAIL] workflows/cross-project-reset.yml missing"
  errors=$((errors + 1))
fi

# Templates are discoverable via CLI
SETUP="$HR_DIR/setup.js"
OUTPUT=$(cd /tmp && CLAUDE_PROJECT_DIR=/tmp node "$SETUP" --workflow list 2>&1)
if echo "$OUTPUT" | grep -q "enforce-shtd"; then
  echo "[OK] enforce-shtd discoverable via CLI"
else
  echo "[FAIL] enforce-shtd not in CLI list: $OUTPUT"
  errors=$((errors + 1))
fi

echo ""
echo "=== Tests complete, $errors error(s) ==="
exit $errors
