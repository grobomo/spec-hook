#!/usr/bin/env bash
# Test: --workflow CLI commands work in hook-runner setup.js
set -euo pipefail

HR_DIR="$HOME/Documents/ProjectsCL1/hook-runner"
SETUP="$HR_DIR/setup.js"

errors=0

# setup.js exists
if [ ! -f "$SETUP" ]; then
  echo "[FAIL] setup.js not found"
  exit 1
fi

# Create temp project with a workflow
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
mkdir -p "$TMPDIR/workflows"

cat > "$TMPDIR/workflows/test-cli.yml" <<'YAML'
name: test-cli
description: Test workflow for CLI commands
version: 1
steps:
  - id: step1
    name: First step
    gate:
      require_files: []
    completion:
      require_files: []
  - id: step2
    name: Second step
    gate:
      require_step: step1
    completion:
      require_files: []
YAML

# --workflow list
OUTPUT=$(cd "$TMPDIR" && node "$SETUP" --workflow list 2>&1)
if echo "$OUTPUT" | grep -q "test-cli"; then
  echo "[OK] --workflow list shows test-cli"
else
  echo "[FAIL] --workflow list didn't show test-cli: $OUTPUT"
  errors=$((errors + 1))
fi

# --workflow start
OUTPUT=$(cd "$TMPDIR" && node "$SETUP" --workflow start test-cli 2>&1)
if echo "$OUTPUT" | grep -q "started\|Started\|step1"; then
  echo "[OK] --workflow start works"
else
  echo "[FAIL] --workflow start: $OUTPUT"
  errors=$((errors + 1))
fi

# --workflow status
OUTPUT=$(cd "$TMPDIR" && node "$SETUP" --workflow status 2>&1)
if echo "$OUTPUT" | grep -q "test-cli"; then
  echo "[OK] --workflow status shows active workflow"
else
  echo "[FAIL] --workflow status: $OUTPUT"
  errors=$((errors + 1))
fi

# --workflow complete
OUTPUT=$(cd "$TMPDIR" && node "$SETUP" --workflow complete step1 2>&1)
if echo "$OUTPUT" | grep -q "completed\|Completed\|step2\|Next"; then
  echo "[OK] --workflow complete step1 works"
else
  echo "[FAIL] --workflow complete: $OUTPUT"
  errors=$((errors + 1))
fi

# --workflow reset
OUTPUT=$(cd "$TMPDIR" && node "$SETUP" --workflow reset 2>&1)
if echo "$OUTPUT" | grep -q "reset\|Reset\|cleared\|Cleared"; then
  echo "[OK] --workflow reset works"
else
  echo "[FAIL] --workflow reset: $OUTPUT"
  errors=$((errors + 1))
fi

echo ""
echo "=== $((5 - errors))/5 tests passed ==="
exit $errors
