#!/usr/bin/env bash
# Run SHTD evidence session — triggers each hook phase and captures output.
# Captures terminal output as text files with system context for screenshot rendering.
#
# Usage: bash run-evidence-session.sh [--docker]
#   --docker: run inside the Docker container instead of native
set -uo pipefail

MODE="native"
[ "${1:-}" = "--docker" ] && MODE="docker"

EVIDENCE_DIR="/tmp/shtd-evidence/${MODE}"
mkdir -p "$EVIDENCE_DIR"

# System info header for every capture
capture_header() {
  echo "┌─────────────────────────────────────────────────────────────"
  echo "│ SHTD Flow Evidence — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "│ Mode: ${MODE} | Host: $(hostname) | IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'N/A')"
  echo "│ User: $(whoami) | Node: $(node --version 2>/dev/null) | Python: $(python3 --version 2>&1 | awk '{print $2}')"
  [ "$MODE" = "docker" ] && echo "│ Container: $(cat /etc/hostname 2>/dev/null || echo 'unknown')"
  echo "└─────────────────────────────────────────────────────────────"
  echo ""
}

run_hook() {
  local hook_name="$1"
  local hook_path="$HOME/.claude/hooks/run-modules/PreToolUse/${hook_name}.js"
  if [ ! -f "$hook_path" ]; then
    hook_path="$HOME/.claude/hooks/run-modules/PostToolUse/${hook_name}.js"
  fi
  if [ ! -f "$hook_path" ]; then
    hook_path="$HOME/.claude/hooks/run-modules/Stop/${hook_name}.js"
  fi
  echo "$hook_path"
}

# Create a test project to work in
TEST_PROJECT="/tmp/shtd-test-project"
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"
git init
git config user.email "evidence@test.local"
git config user.name "Evidence Test"
echo "# Test" > README.md
git add . && git commit -m "init"

export CLAUDE_PROJECT_DIR="$TEST_PROJECT"

echo "=========================================="
echo "  SHTD Evidence Session — ${MODE}"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

# ─── Evidence 1: install.sh --check ───
echo ""
echo "━━━ Evidence 1: Installation Verification ━━━"
{
  capture_header
  echo "$ bash install.sh --check"
  echo ""
  cd /tmp/spec-hook && bash install.sh --check 2>&1
  cd "$TEST_PROJECT"
} | tee "$EVIDENCE_DIR/01-install-check.txt"

# ─── Evidence 2: branch-gate BLOCKS on main ───
echo ""
echo "━━━ Evidence 2: branch-gate blocks code on main ━━━"
{
  capture_header
  echo "$ git branch"
  git branch
  echo ""
  echo ">>> Simulating Claude Write to src/app.js on main branch <<<"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_PROJECT"'/src/app.js","content":"hello"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_branch-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/02-branch-gate-block.txt"

# ─── Evidence 3: spec-gate BLOCKS without specs/ ───
echo ""
echo "━━━ Evidence 3: spec-gate blocks without specs/ ━━━"
{
  capture_header
  # Switch to feature branch
  git checkout -b 001-test-feature
  echo "$ git branch"
  git branch
  echo ""
  echo ">>> Simulating Claude Write to src/app.js without specs/ <<<"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_PROJECT"'/src/app.js","content":"hello"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_spec-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/03-spec-gate-block.txt"

# ─── Evidence 4: spec-gate ALLOWS with specs/ ───
echo ""
echo "━━━ Evidence 4: spec-gate allows with specs/ ━━━"
{
  capture_header
  mkdir -p "$TEST_PROJECT/specs/001-test-feature"
  echo "# Test Spec" > "$TEST_PROJECT/specs/001-test-feature/spec.md"
  echo "$ ls specs/"
  ls specs/
  echo ""
  echo ">>> Simulating Claude Write to src/app.js WITH specs/ <<<"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_PROJECT"'/src/app.js","content":"hello"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_spec-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/04-spec-gate-allow.txt"

# ─── Evidence 5: remote-tracking-gate BLOCKS untracked branch ───
echo ""
echo "━━━ Evidence 5: remote-tracking-gate blocks untracked branch ━━━"
{
  capture_header
  echo "$ git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>&1 || echo 'No upstream'"
  git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>&1 || echo "No upstream"
  echo ""
  echo ">>> Simulating Claude Write on untracked feature branch <<<"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_PROJECT"'/src/app.js","content":"hello"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_remote-tracking-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/05-tracking-gate-block.txt"

# ─── Evidence 6: secret-scan-gate BLOCKS push without CI ───
echo ""
echo "━━━ Evidence 6: secret-scan-gate blocks push without secret-scan.yml ━━━"
{
  capture_header
  echo "$ ls .github/workflows/ 2>/dev/null || echo 'No workflows dir'"
  ls .github/workflows/ 2>/dev/null || echo "No workflows dir"
  echo ""
  echo ">>> Simulating Claude Bash: git push origin main <<<"
  echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_secret-scan-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/06-secret-scan-block.txt"

# ─── Evidence 7: pr-per-task-gate BLOCKS PR without task ID ───
echo ""
echo "━━━ Evidence 7: pr-per-task-gate blocks PR without task ID ━━━"
{
  capture_header
  echo ">>> Simulating Claude Bash: gh pr create --title 'Add feature' <<<"
  echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title '\''Add feature'\'' --body '\''...'\''"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_pr-per-task-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
  echo ""
  echo ">>> Now with task ID: gh pr create --title 'T001: Add feature' <<<"
  echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title '\''T001: Add feature'\'' --body '\''...'\''"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_pr-per-task-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/07-pr-task-gate.txt"

# ─── Evidence 8: e2e-merge-gate BLOCKS merge without evidence ───
echo ""
echo "━━━ Evidence 8: e2e-merge-gate blocks feature merge without evidence ━━━"
{
  capture_header
  echo ">>> Simulating Claude Bash: gh pr merge on feature branch 001-test-feature <<<"
  echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_e2e-merge-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
  echo ""
  echo ">>> Now with .test-results/001-test-feature.passed <<<"
  mkdir -p "$TEST_PROJECT/.test-results"
  echo "passed $(date -u)" > "$TEST_PROJECT/.test-results/001-test-feature.passed"
  echo '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --squash"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_e2e-merge-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED');
      }
    "
} | tee "$EVIDENCE_DIR/08-e2e-merge-gate.txt"

# ─── Evidence 9: workflow-gate enforces step order ───
echo ""
echo "━━━ Evidence 9: workflow-gate enforces step order ━━━"
{
  capture_header
  # Create a test workflow
  mkdir -p "$TEST_PROJECT/workflows"
  cat > "$TEST_PROJECT/workflows/test-pipeline.yml" << 'YAML'
name: test-pipeline
steps:
  - id: build
    name: Build artifacts
    gate:
      require_files: []
    completion:
      require_files: ["build-done.txt"]
  - id: test
    name: Run tests
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
YAML

  # Start workflow
  WORKFLOW_JS="$HOME/.claude/shtd-flow/lib/workflow.js"
  node -e "
    const wf = require('$WORKFLOW_JS');
    wf.initState('test-pipeline', '$TEST_PROJECT/workflows/test-pipeline.yml', '$TEST_PROJECT');
    console.log('Workflow started. Current step:', wf.currentStep('$TEST_PROJECT'));
    console.log('State:', JSON.stringify(wf.readState('$TEST_PROJECT'), null, 2));
  "
  echo ""
  echo ">>> Attempting to Write during 'deploy' step (should block — build not done) <<<"
  # Complete build, skip test, try deploy
  node -e "
    const wf = require('$WORKFLOW_JS');
    wf.completeStep('build', '$TEST_PROJECT');
    console.log('Build step completed. Current step:', wf.currentStep('$TEST_PROJECT'));
  "
  echo ""
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TEST_PROJECT"'/deploy.sh","content":"deploy"}}' | \
    node -e "
      process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT';
      const m = require('$(run_hook shtd_workflow-gate)');
      const input = JSON.parse(require('fs').readFileSync(0,'utf-8'));
      const result = m(input);
      console.log('Hook result:', JSON.stringify(result, null, 2));
      if (result && result.decision === 'block') {
        console.log('');
        console.log('✗ BLOCKED: ' + result.reason);
      } else {
        console.log('✓ ALLOWED (test step gate satisfied — build is done)');
      }
    "
} | tee "$EVIDENCE_DIR/09-workflow-gate.txt"

# ─── Evidence 10: audit log shows full event chain ───
echo ""
echo "━━━ Evidence 10: Audit log captures events ━━━"
{
  capture_header
  AUDIT_FILE="$HOME/.claude/shtd-flow/audit.jsonl"
  echo "$ tail -20 $AUDIT_FILE"
  if [ -f "$AUDIT_FILE" ]; then
    tail -20 "$AUDIT_FILE" | python3 -m json.tool --no-ensure-ascii 2>/dev/null || tail -20 "$AUDIT_FILE"
  else
    echo "(No audit events yet — audit log created on first event)"
  fi
  echo ""
  echo "$ wc -l $AUDIT_FILE"
  wc -l "$AUDIT_FILE" 2>/dev/null || echo "0"
} | tee "$EVIDENCE_DIR/10-audit-log.txt"

# ─── Summary ───
echo ""
echo "=========================================="
echo "  Evidence Session Complete — ${MODE}"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Captures saved to: $EVIDENCE_DIR"
echo "=========================================="
ls -la "$EVIDENCE_DIR"

# Cleanup workflow state
rm -f "$TEST_PROJECT/.shtd-workflow-state.json"
