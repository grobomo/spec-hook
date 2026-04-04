#!/usr/bin/env bash
# Test T026: Code review fixes — DRY worker config, no stale scripts, audit regex tightened
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

echo "=== T026: Code Review Fixes ==="
echo ""

# 1. worker-config.sh exists and is sourceable
echo "--- 1. Shared worker config ---"
if [ -f "$PROJECT_DIR/scripts/worker-config.sh" ]; then
  # Source it and check that WORKER_IPS is populated
  (
    source "$PROJECT_DIR/scripts/worker-config.sh"
    if [ "${#WORKER_IPS[@]}" -eq 4 ]; then
      exit 0
    else
      exit 1
    fi
  ) && pass "worker-config.sh has 4 worker IPs" || fail "worker-config.sh missing IPs"
else
  fail "worker-config.sh not found"
fi

# 2. Scripts that use worker IPs source from worker-config.sh (no hardcoded IPs)
echo ""
echo "--- 2. No hardcoded IPs in worker scripts ---"
for script in deploy-to-worker.sh deploy-to-all-workers.sh check-worker-install.sh; do
  if [ -f "$PROJECT_DIR/scripts/$script" ]; then
    if grep -q 'worker-config.sh' "$PROJECT_DIR/scripts/$script"; then
      pass "$script sources worker-config.sh"
    else
      fail "$script doesn't source worker-config.sh"
    fi
    # Should NOT have its own declare -A IPS or WORKER_IPS
    if grep -q 'declare -A.*IPS' "$PROJECT_DIR/scripts/$script"; then
      fail "$script has hardcoded IP array"
    else
      pass "$script has no hardcoded IP array"
    fi
  fi
done

# 3. Stale scripts archived
echo ""
echo "--- 3. Stale scripts archived ---"
for stale in deploy-to-workers.sh verify-worker.sh; do
  if [ -f "$PROJECT_DIR/scripts/$stale" ]; then
    fail "$stale still in scripts/ (should be archived)"
  else
    pass "$stale archived"
  fi
done

# 4. Audit logger regex tightened (no bare /test/i)
echo ""
echo "--- 4. Audit logger regex ---"
AUDIT_LOGGER="$PROJECT_DIR/hooks/PostToolUse/shtd_audit-logger.js"
if [ -f "$AUDIT_LOGGER" ]; then
  # Should NOT have bare /test/i (without path separators)
  if grep -P '\/test\/i' "$AUDIT_LOGGER" | grep -qv '[\/\\\\]'; then
    fail "audit-logger.js still uses bare /test/i regex"
  else
    pass "audit-logger.js regex is path-bounded"
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
