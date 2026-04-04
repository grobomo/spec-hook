#!/usr/bin/env bash
# E2E Proof Test — Verifies hooks block real scenarios and audit captures everything
#
# This test creates a real git repo, installs SHTD, then simulates the exact
# JSON inputs that Claude Code sends to PreToolUse hooks. It proves:
#   1. Each gate blocks when it should (with the exact tool_name/tool_input format)
#   2. Each gate allows when conditions are met
#   3. The audit log captures a complete workflow chain
#   4. The workflow engine enforces step order with real state transitions
#
# No mocks. Real git repo. Real hook modules. Real file system state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
NP=$(to_node "$PROJECT_DIR")

TMPDIR=$(mktemp -d)
NT=$(to_node "$TMPDIR")
ERRORS=0
TOTAL=0

pass() { TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL+1)); ERRORS=$((ERRORS+1)); echo "  FAIL: $1"; }
section() { echo ""; echo "=== $1 ==="; }

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# ---- Setup: Real git repo with SHTD installed ----
section "Setup"
cd "$TMPDIR"
git init -q fake-project
cd fake-project
git commit --allow-empty -m "init" -q
FAKE_DIR=$(to_node "$(pwd)")

# Point hooks at repo source (not installed location)
HOOKS_DIR="${NP}/hooks"

# Helper: invoke a hook module with a JSON input, capture output
invoke_hook() {
  local hook_path="$1"
  local json_input="$2"
  node -e "
    process.env.CLAUDE_PROJECT_DIR = '${FAKE_DIR}';
    delete require.cache[require.resolve('${hook_path}')];
    const hook = require('${hook_path}');
    const result = hook(${json_input});
    console.log(JSON.stringify(result));
  " 2>&1
}

# ================================================================
section "1. spec-gate: blocks code edit without specs/"
# ================================================================

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_spec-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Write to src/app.js BLOCKED — no specs/ directory" \
  || fail "Expected block, got: $RESULT"

# Now create specs
mkdir -p specs/001-feature
echo "# Spec" > specs/001-feature/spec.md

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_spec-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
[ "$RESULT" = "null" ] \
  && pass "Write to src/app.js ALLOWED — specs/ exists" \
  || fail "Expected allow, got: $RESULT"

# ================================================================
section "2. branch-gate: blocks code edit on main"
# ================================================================

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_branch-gate.js" \
  '{"tool_name":"Edit","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Edit on main BLOCKED" \
  || fail "Expected block on main, got: $RESULT"

# Docs are always allowed on main
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_branch-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/TODO.md"'"}}')
[ "$RESULT" = "null" ] \
  && pass "TODO.md ALLOWED on main" \
  || fail "Expected allow for TODO.md, got: $RESULT"

# Switch to feature branch
git checkout -q -b 001-add-feature

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_branch-gate.js" \
  '{"tool_name":"Edit","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
[ "$RESULT" = "null" ] \
  && pass "Edit on feature branch ALLOWED" \
  || fail "Expected allow on feature branch, got: $RESULT"

# ================================================================
section "3. pr-per-task-gate: requires task ID in PR title"
# ================================================================

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_pr-per-task-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title '\''Add new feature'\'' --body '\''stuff'\''."}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "PR without task ID BLOCKED" \
  || fail "Expected block, got: $RESULT"

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_pr-per-task-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title '\''T001: Add new feature'\'' --body '\''stuff'\''."}}')
[ "$RESULT" = "null" ] \
  && pass "PR with T001 in title ALLOWED" \
  || fail "Expected allow, got: $RESULT"

# ================================================================
section "4. secret-scan-gate: blocks push without secret-scan.yml"
# ================================================================

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_secret-scan-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Push without secret-scan.yml BLOCKED" \
  || fail "Expected block, got: $RESULT"

mkdir -p .github/workflows
echo "name: scan" > .github/workflows/secret-scan.yml

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_secret-scan-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')
[ "$RESULT" = "null" ] \
  && pass "Push with secret-scan.yml ALLOWED" \
  || fail "Expected allow, got: $RESULT"

# ================================================================
section "5. remote-tracking-gate: blocks edits on untracked branch"
# ================================================================

# We're on 001-add-feature which has no remote tracking
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_remote-tracking-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Write on untracked branch BLOCKED" \
  || fail "Expected block on untracked branch, got: $RESULT"

echo "$RESULT" | grep -q 'git push -u' \
  && pass "Block message suggests git push -u" \
  || fail "Missing push -u hint in: $RESULT"

# Docs should be allowed even on untracked branch
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_remote-tracking-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/TODO.md"'"}}')
[ "$RESULT" = "null" ] \
  && pass "TODO.md ALLOWED on untracked branch" \
  || fail "Expected allow for docs, got: $RESULT"

# Main should always be allowed (it always tracks remote)
git checkout -q main
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_remote-tracking-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/app.js"'"}}')
[ "$RESULT" = "null" ] \
  && pass "Write on main ALLOWED (always has tracking)" \
  || fail "Expected allow on main, got: $RESULT"

git checkout -q 001-add-feature

# ================================================================
section "6. e2e-merge-gate: blocks feature merge without evidence"
# ================================================================

# Try to merge feature branch to main without E2E evidence
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_e2e-merge-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Feature merge BLOCKED — no .test-results/ evidence" \
  || fail "Expected block, got: $RESULT"

echo "$RESULT" | grep -q 'test-results' \
  && pass "Block message mentions .test-results/" \
  || fail "Missing test-results hint in: $RESULT"

# Create E2E evidence
mkdir -p .test-results
touch ".test-results/001-add-feature.passed"

RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_e2e-merge-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash"}}')
[ "$RESULT" = "null" ] \
  && pass "Feature merge ALLOWED — evidence exists" \
  || fail "Expected allow with evidence, got: $RESULT"

# Task branches (NNN-TNNN-slug) should NOT be gated
git checkout -q -b 001-T001-add-login
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_e2e-merge-gate.js" \
  '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash"}}')
[ "$RESULT" = "null" ] \
  && pass "Task branch merge ALLOWED (not feature branch)" \
  || fail "Expected allow for task branch, got: $RESULT"

git checkout -q 001-add-feature

# ================================================================
section "7. workflow-gate: enforces step order"
# ================================================================

# Create a workflow
WF_JS="${NP}/lib/workflow.js"
mkdir -p workflows
cat > workflows/deploy.yml << 'WFEOF'
name: deploy
description: test deploy workflow
version: 1
steps:
  - id: build
    name: Build
    gate:
      require_files: []
    completion:
      require_files: ["build-done.txt"]
  - id: test
    name: Test
    gate:
      require_step: build
    completion:
      require_files: ["test-done.txt"]
  - id: deploy
    name: Deploy
    gate:
      require_step: test
    completion:
      require_files: ["deploy-done.txt"]
WFEOF

WF_YML="${FAKE_DIR}/workflows/deploy.yml"

# Start workflow
node -e "
  const wf = require('${WF_JS}');
  wf.initState('deploy', '${WF_YML}', '${FAKE_DIR}');
"

# Current step is 'build' — gate is open (no prereqs)
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_workflow-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/build.js"'"}}')
[ "$RESULT" = "null" ] \
  && pass "Write ALLOWED — build step gate open (no prereqs)" \
  || fail "Expected allow for build step, got: $RESULT"

# Complete build, but don't complete test — deploy gate should block
touch build-done.txt
node -e "const wf = require('${WF_JS}'); wf.completeStep('build', '${FAKE_DIR}');"

# Test step is now current — gate open (build is done)
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_workflow-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/test.js"'"}}')
[ "$RESULT" = "null" ] \
  && pass "Write ALLOWED — test step gate open (build done)" \
  || fail "Expected allow for test step, got: $RESULT"

# Skip test, try to force-advance to deploy
node -e "
  const wf = require('${WF_JS}');
  const state = wf.readState('${FAKE_DIR}');
  // Manually set deploy as current without completing test
  state.steps.test.status = 'pending';
  state.steps.deploy.status = 'in_progress';
  wf.writeState(state, '${FAKE_DIR}');
"

# Deploy gate should block — test step not completed
RESULT=$(invoke_hook "${HOOKS_DIR}/PreToolUse/shtd_workflow-gate.js" \
  '{"tool_name":"Write","tool_input":{"file_path":"'"${FAKE_DIR}/src/deploy.js"'"}}')
echo "$RESULT" | grep -q '"decision":"block"' \
  && pass "Write BLOCKED — deploy gate requires test step" \
  || fail "Expected block for skipped step, got: $RESULT"

echo "$RESULT" | grep -q 'test' \
  && pass "Block message mentions missing 'test' step" \
  || fail "Block message doesn't explain what's missing: $RESULT"

# ================================================================
section "8. audit-logger: captures workflow events"
# ================================================================

# Set up audit to write to our temp dir
AUDIT_HOME="${NT}"
mkdir -p "$TMPDIR/.claude/shtd-flow"

AUDIT_JS="${NP}/lib/audit.js"

# Simulate a sequence of workflow events
# HOME and USERPROFILE must both be set for os.homedir() on Windows
HOME="${NT}" USERPROFILE="${NT}" node -e "
  process.env.HOME = '${NT}';
  process.env.USERPROFILE = '${NT}';
  process.env.CLAUDE_PROJECT_DIR = '${FAKE_DIR}';
  delete require.cache[require.resolve('${AUDIT_JS}')];
  const audit = require('${AUDIT_JS}');
  audit.logEvent('spec_created', {file: 'spec.md', task: 'T001'});
  audit.logEvent('tasks_defined', {file: 'tasks.md', task: 'T001'});
  audit.logEvent('test_created', {file: 'test-T001.sh', task: 'T001'});
  audit.logEvent('branch_created', {branch: '001-add-feature'});
  audit.logEvent('code_blocked', {reason: 'no_test_for_task', task: 'T001'});
  audit.logEvent('pr_opened', {title: 'T001: Add feature', task: 'T001'});
  audit.logEvent('e2e_passed', {task: 'T001'});
  audit.logEvent('pr_merged', {task: 'T001'});
"

AUDIT_FILE="$TMPDIR/.claude/shtd-flow/audit.jsonl"
LINES=$(wc -l < "$AUDIT_FILE")
[ "$LINES" -eq 8 ] \
  && pass "Audit log has 8 events (complete workflow chain)" \
  || fail "Expected 8 events, got $LINES"

# Verify event order tells the story
EVENTS=$(HOME="${NT}" USERPROFILE="${NT}" node -e "
  process.env.HOME = '${NT}';
  process.env.USERPROFILE = '${NT}';
  delete require.cache[require.resolve('${AUDIT_JS}')];
  const a = require('${AUDIT_JS}');
  const events = a.readEvents('fake-project');
  console.log(events.map(e => e.event).join(','));
")
EXPECTED="spec_created,tasks_defined,test_created,branch_created,code_blocked,pr_opened,e2e_passed,pr_merged"
[ "$EVENTS" = "$EXPECTED" ] \
  && pass "Audit event chain: spec→tasks→test→branch→blocked→PR→e2e→merge" \
  || fail "Wrong event chain: $EVENTS"

# Verify each event has timestamp, project, session
FIRST=$(head -1 "$AUDIT_FILE")
echo "$FIRST" | grep -q '"ts"' && echo "$FIRST" | grep -q '"project"' \
  && pass "Events include timestamp and project" \
  || fail "Missing required fields in: $FIRST"

# ================================================================
section "9. Full workflow lifecycle via CLI"
# ================================================================

CLI="${NP}/scripts/shtd-workflow.sh"

# Reset workflow state
rm -f "${TMPDIR}/fake-project/.shtd-workflow-state.json"

# Recreate workflow (the previous test mangled state)
node -e "
  const wf = require('${WF_JS}');
  wf.initState('deploy', '${WF_YML}', '${FAKE_DIR}');
"

STATUS=$(bash "$CLI" status "$TMPDIR/fake-project" 2>&1)
echo "$STATUS" | grep -q "deploy" \
  && pass "CLI status shows active workflow" \
  || fail "CLI status: $STATUS"
echo "$STATUS" | grep -q "build" \
  && pass "CLI status shows build step" \
  || fail "Missing build step in: $STATUS"

# Complete build via CLI
bash "$CLI" complete build "$TMPDIR/fake-project" >/dev/null 2>&1
STATUS=$(bash "$CLI" status "$TMPDIR/fake-project" 2>&1)
echo "$STATUS" | grep -q "completed" \
  && pass "CLI complete marks step done" \
  || fail "Build not completed in: $STATUS"

# Reset
bash "$CLI" reset "$TMPDIR/fake-project" >/dev/null 2>&1
[ ! -f "$TMPDIR/fake-project/.shtd-workflow-state.json" ] \
  && pass "CLI reset clears state" \
  || fail "State file still exists after reset"

# ================================================================
section "Summary"
# ================================================================
echo ""
echo "Total: $TOTAL tests"
if [ $ERRORS -eq 0 ]; then
  echo "ALL PASSED — every gate blocks when it should, allows when conditions are met,"
  echo "audit captures the full chain, and workflow step order is enforced."
  exit 0
else
  echo "$ERRORS FAILED"
  exit 1
fi
