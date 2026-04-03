#!/usr/bin/env bash
# Workflow step: test — Run SHTD verification suite on remote instance
# Tests that hooks load, gates fire, audit log works, and task claims work.
#
# Requires: install-verified.txt
# Produces: .test-results/remote-install.passed

set -euo pipefail

PROJECT_DIR="${1:-.}"
IP=$(cat "${PROJECT_DIR}/instance-ip.txt")
SSH_KEY="${HOME}/.ssh/claude-portable.pem"
MODE="${INSTALL_MODE:-container}"

ssh_cmd() {
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" ubuntu@"$IP" "$@"
}

docker_exec() {
  ssh_cmd "docker exec claude-portable bash -c '$*'"
}

run_remote() {
  if [ "$MODE" = "container" ]; then docker_exec "$@"; else ssh_cmd "$@"; fi
}

# Remote HOME varies: container uses REMOTE_HOME from env, native uses ~
REMOTE_HOME="${REMOTE_HOME:-\$HOME}"

echo "Running SHTD verification on ${IP}..."

ERRORS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS+1)); }

# Test 1: audit.js loads
run_remote "node -e \"require('${REMOTE_HOME}/.claude/shtd-flow/lib/audit.js')\"" 2>/dev/null \
  && pass "audit.js loads" || fail "audit.js"

# Test 2: task_claims.py runs
run_remote "python3 ${REMOTE_HOME}/.claude/shtd-flow/lib/task_claims.py status --project-dir /tmp" 2>/dev/null \
  && pass "task_claims.py runs" || fail "task_claims.py"

# Test 3: Hook modules exist
for hook in shtd_spec-gate.js shtd_branch-gate.js shtd_workflow-gate.js; do
  run_remote "test -f ${REMOTE_HOME}/.claude/hooks/run-modules/PreToolUse/${hook}" 2>/dev/null \
    && pass "${hook} installed" || fail "${hook} missing"
done

# Test 4: Audit log works
run_remote "node -e \"
  const a = require('${REMOTE_HOME}/.claude/shtd-flow/lib/audit.js');
  a.logEvent('test_event', {source: 'remote-test'});
  const events = a.readEvents(null, 5);
  if (events.some(e => e.event === 'test_event')) process.exit(0);
  process.exit(1);
\"" 2>/dev/null && pass "Audit log write/read" || fail "Audit log"

# Test 5: Workflow engine loads
run_remote "node -e \"require('${REMOTE_HOME}/.claude/shtd-flow/lib/workflow.js')\"" 2>/dev/null \
  && pass "workflow.js loads" || { fail "workflow.js"; }

echo ""
mkdir -p "${PROJECT_DIR}/.test-results"
if [ $ERRORS -eq 0 ]; then
  echo "All remote tests passed."
  echo "passed $(date -Iseconds)" > "${PROJECT_DIR}/.test-results/remote-install.passed"
else
  echo "${ERRORS} remote test(s) failed."
  exit 1
fi
