#!/usr/bin/env bash
# Test T027: Evidence deployment — verify provisioning and evidence capture scripts exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

echo "=== T027: Evidence Deploy Scripts ==="
echo ""

# 1. Provisioning script exists
echo "--- 1. AWS provisioning script ---"
if [ -f "$PROJECT_DIR/scripts/aws/provision-evidence-instance.sh" ]; then
  pass "provision-evidence-instance.sh exists"
else
  fail "provision-evidence-instance.sh missing"
fi

# 2. Evidence capture script exists
echo ""
echo "--- 2. Evidence capture script ---"
if [ -f "$PROJECT_DIR/scripts/run-evidence-session.sh" ]; then
  pass "run-evidence-session.sh exists"
else
  fail "run-evidence-session.sh missing"
fi

# 3. Screenshot rendering script exists
echo ""
echo "--- 3. Screenshot renderer ---"
if [ -f "$PROJECT_DIR/scripts/render-terminal-screenshot.py" ]; then
  pass "render-terminal-screenshot.py exists"
else
  fail "render-terminal-screenshot.py missing"
fi

# 4. Report generator handles evidence screenshots
echo ""
echo "--- 4. Report generator ---"
if [ -f "$PROJECT_DIR/scripts/generate-evidence-report.py" ]; then
  pass "generate-evidence-report.py exists"
else
  fail "generate-evidence-report.py missing"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
