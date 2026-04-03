#!/usr/bin/env bash
# Test: Remote SHTD install on EC2 CCC worker
# Usage: bash test-T011-remote-install.sh IP [MODE] [SSH_KEY]
#   MODE: container (default) or native
set -euo pipefail

IP="${1:?Usage: test-T011-remote-install.sh IP [MODE] [SSH_KEY]}"
MODE="${2:-container}"
SSH_KEY="${3:-${HOME}/.ssh/ccc-keys/worker-5.pem}"
ERRORS=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }

ssh_cmd() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" ubuntu@"$IP" "$@" 2>/dev/null
}

docker_exec() {
  ssh_cmd "docker exec claude-portable bash -c '$*'"
}

# For Node commands: skip bash -c wrapper to avoid quote mangling
docker_node() {
  ssh_cmd "docker exec claude-portable node -e '$*'"
}

run_remote() {
  if [ "$MODE" = "container" ]; then docker_exec "$@"; else ssh_cmd "$@"; fi
}

run_node() {
  if [ "$MODE" = "container" ]; then docker_node "$@"; else ssh_cmd "node -e '$*'"; fi
}

echo "=== SHTD Remote Install Test ==="
echo "Target: ${IP} (mode: ${MODE})"
echo ""

# Step 1: Check SSH connectivity
echo "--- Connectivity ---"
ssh_cmd "echo ok" && pass "SSH connects" || { fail "SSH unreachable"; echo "${ERRORS} failures"; exit 1; }

# Step 2: Check container (if container mode)
if [ "$MODE" = "container" ]; then
  STATUS=$(ssh_cmd "docker ps --filter name=claude-portable --format '{{.Status}}'" || echo "")
  if [[ "$STATUS" == Up* ]]; then
    pass "Docker container running"
  else
    fail "Docker container not running: $STATUS"
    echo "Trying native mode instead..."
    MODE="native"
  fi
fi

# Resolve remote HOME (avoids $HOME expansion across SSH/docker quoting layers)
RHOME=$(run_remote 'echo $HOME' 2>/dev/null || echo "")
if [ -z "$RHOME" ]; then
  RHOME=$(run_remote "python3 -c 'import os; print(os.path.expanduser(\"~\"))'" 2>/dev/null || echo "/home/ubuntu")
fi
echo "Remote HOME: ${RHOME}"

# Step 3: Clone spec-hook and install
echo ""
echo "--- Install ---"
run_remote "rm -rf /tmp/spec-hook" || true
run_remote "git clone https://github.com/grobomo/spec-hook.git /tmp/spec-hook" \
  && pass "Cloned spec-hook" || fail "Clone failed"

INSTALL_OUT=$(run_remote "cd /tmp/spec-hook && bash install.sh" 2>&1 || true)
INSTALL_CLEAN=$(echo "$INSTALL_OUT" | sed 's/\x1b\[[0-9;]*m//g')
echo "$INSTALL_CLEAN" | grep -q "\[FAIL\]" && fail "install.sh had failures" || pass "SHTD install.sh completed"

# Step 4: Verify installation
echo ""
echo "--- Verify ---"
VERIFY_OUT=$(run_remote "cd /tmp/spec-hook && bash install.sh --check" 2>&1 || true)
echo "$VERIFY_OUT" | grep -q "FAIL" && fail "Verification has failures" || pass "Verification clean"

# Step 5: Test individual components
echo ""
echo "--- Components ---"
H='process.env.HOME'
run_node "require(${H} + \"/.claude/shtd-flow/lib/audit.js\")" \
  && pass "audit.js loads" || fail "audit.js"

run_remote "python3 ~/.claude/shtd-flow/lib/task_claims.py status --project-dir /tmp" \
  && pass "task_claims.py runs" || fail "task_claims.py"

run_node "require(${H} + \"/.claude/shtd-flow/lib/workflow.js\")" \
  && pass "workflow.js loads" || fail "workflow.js"

# Step 6: Test audit log write/read
run_node "
  const a = require(${H} + \"/.claude/shtd-flow/lib/audit.js\");
  a.logEvent(\"remote_test\", {source: \"test-T011\"});
  const events = a.readEvents(null, 5);
  if (events.some(e => e.event === \"remote_test\")) process.exit(0);
  process.exit(1);
" && pass "Audit write/read" || fail "Audit write/read"

# Step 7: Test hook modules are in place
for hook in shtd_spec-gate.js shtd_branch-gate.js shtd_workflow-gate.js shtd_task-claim.js; do
  run_remote "test -f ${RHOME}/.claude/hooks/run-modules/PreToolUse/${hook}" \
    && pass "${hook}" || fail "${hook} missing"
done

run_remote "test -f ${RHOME}/.claude/hooks/run-modules/PostToolUse/shtd_audit-logger.js" \
  && pass "shtd_audit-logger.js" || fail "audit-logger missing"

run_remote "test -f ${RHOME}/.claude/hooks/run-modules/Stop/shtd_task-release.js" \
  && pass "shtd_task-release.js" || fail "task-release missing"

# Summary
echo ""
echo "=== Results ==="
if [ $ERRORS -eq 0 ]; then
  echo "All tests passed on ${IP} (${MODE} mode)."
  exit 0
else
  echo "${ERRORS} test(s) failed."
  exit 1
fi
