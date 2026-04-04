#!/usr/bin/env bash
# Capture REAL terminal screenshots using xvfb + xterm + scrot.
# Each evidence scenario runs in an actual xterm window and is captured
# as a real screen grab — not rendered text.
#
# Usage: bash capture-real-screenshots.sh [--docker]
#   Run ON the EC2 instance (not locally).

set -uo pipefail

MODE="native"
[ "${1:-}" = "--docker" ] && MODE="docker"

EVIDENCE_DIR="/tmp/shtd-evidence-screenshots/${MODE}"
mkdir -p "$EVIDENCE_DIR"

# Ensure xvfb + xterm + scrot are installed
if ! command -v Xvfb >/dev/null 2>&1; then
  echo "Installing xvfb, xterm, scrot, imagemagick..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb xterm scrot imagemagick fonts-dejavu-core
fi

# Start virtual framebuffer (1280x960 resolution)
export DISPLAY=:99
Xvfb :99 -screen 0 1280x960x24 &
XVFB_PID=$!
sleep 1

# Helper: run a command in xterm, wait, then screenshot
capture() {
  local name="$1"
  local title="$2"
  shift 2
  local cmd="$*"

  echo "  Capturing: $name — $title"

  # Run the command in xterm with a visible title and large font
  # -hold keeps the window open after command finishes
  xterm -hold \
    -title "$title" \
    -fa "DejaVu Sans Mono" -fs 11 \
    -geometry 120x40+0+0 \
    -bg '#1e1e2e' -fg '#cdd6f4' \
    -e bash -c "$cmd; echo ''; echo '─── $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC) ── $(hostname) ── $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo N/A) ───'" &
  XTERM_PID=$!

  # Wait for xterm to render
  sleep 2

  # Take actual screenshot of the entire display
  scrot "$EVIDENCE_DIR/${name}.png" -z

  # Kill the xterm
  kill $XTERM_PID 2>/dev/null || true
  wait $XTERM_PID 2>/dev/null || true

  # Crop to just the xterm window area (remove empty space)
  convert "$EVIDENCE_DIR/${name}.png" -trim +repage "$EVIDENCE_DIR/${name}.png" 2>/dev/null || true
}

# --- Setup: create test project ---
TEST_PROJECT="/tmp/shtd-test-project-${MODE}"
rm -rf "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"
git init -b master
git config user.email "evidence@test.local"
git config user.name "Evidence Test"
echo "# Test" > README.md
git add . && git commit -m "init"

export CLAUDE_PROJECT_DIR="$TEST_PROJECT"
HOOKS_DIR="$HOME/.claude/hooks/run-modules/PreToolUse"

echo "=========================================="
echo "  SHTD Real Screenshot Capture — ${MODE}"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

# --- Evidence 1: install.sh --check ---
capture "01-install-check" "SHTD Install Verification" \
  "echo '=== SHTD Flow — Installation Check ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Date: '\$(date -u) && echo '' && cd /tmp/spec-hook && bash install.sh --check"

# --- Evidence 2: branch-gate BLOCKS on master ---
capture "02-branch-gate-block" "branch-gate: BLOCKS on master" \
  "cd $TEST_PROJECT && echo '=== branch-gate: Code Edit on master ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Branch: '\$(git branch --show-current) && echo '' && echo 'Input: Write src/app.js on master' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_PROJECT/src/app.js\",\"content\":\"hello\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_branch-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log(''); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 3: spec-gate BLOCKS without specs/ ---
cd "$TEST_PROJECT" && git checkout -b 001-test-feature 2>/dev/null || true

capture "03-spec-gate-block" "spec-gate: BLOCKS without specs/" \
  "cd $TEST_PROJECT && echo '=== spec-gate: No specs/ directory ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Branch: '\$(git branch --show-current) && echo 'specs/ exists?: '\$(ls -d specs 2>/dev/null || echo NO) && echo '' && echo 'Input: Write src/app.js' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_PROJECT/src/app.js\",\"content\":\"hello\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_spec-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log(''); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 4: spec-gate ALLOWS with specs/ ---
mkdir -p "$TEST_PROJECT/specs/001-test-feature"
echo "# Test Spec" > "$TEST_PROJECT/specs/001-test-feature/spec.md"

capture "04-spec-gate-allow" "spec-gate: ALLOWS with specs/" \
  "cd $TEST_PROJECT && echo '=== spec-gate: With specs/ present ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Branch: '\$(git branch --show-current) && echo 'specs/ contents:' && ls specs/ && echo '' && echo 'Input: Write src/app.js' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_PROJECT/src/app.js\",\"content\":\"hello\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_spec-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log(''); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 5: remote-tracking-gate BLOCKS ---
capture "05-tracking-gate-block" "remote-tracking-gate: BLOCKS untracked branch" \
  "cd $TEST_PROJECT && echo '=== remote-tracking-gate: Untracked branch ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Branch: '\$(git branch --show-current) && echo 'Upstream: '\$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>&1 || echo NONE) && echo '' && echo 'Input: Write src/app.js' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_PROJECT/src/app.js\",\"content\":\"hello\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_remote-tracking-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log(''); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 6: secret-scan-gate BLOCKS ---
capture "06-secret-scan-block" "secret-scan-gate: BLOCKS push without CI" \
  "cd $TEST_PROJECT && echo '=== secret-scan-gate: No CI workflow ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo '.github/workflows/: '\$(ls .github/workflows/ 2>/dev/null || echo 'DOES NOT EXIST') && echo '' && echo 'Input: Bash git push origin main' && echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_secret-scan-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log(''); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 7: pr-per-task-gate ---
capture "07-pr-task-gate" "pr-per-task-gate: Block without task ID, allow with T001" \
  "cd $TEST_PROJECT && echo '=== pr-per-task-gate ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo '' && echo '--- Test 1: PR without task ID ---' && echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr create --title '\\''Add feature'\\'' --body '\\''...'\\''\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_pr-per-task-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); if(r&&r.decision==='block'){console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\" && echo '' && echo '--- Test 2: PR WITH task ID T001 ---' && echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr create --title '\\''T001: Add feature'\\'' --body '\\''...'\\''\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_pr-per-task-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); if(r&&r.decision==='block'){console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 8: e2e-merge-gate ---
capture "08-e2e-merge-gate" "e2e-merge-gate: Block without evidence, allow with" \
  "cd $TEST_PROJECT && echo '=== e2e-merge-gate ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo '' && echo '--- Without .test-results/ evidence ---' && echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr merge --squash\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_e2e-merge-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); console.log('Hook result:'); console.log(JSON.stringify(r,null,2)); if(r&&r.decision==='block'){console.log(''); console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\" && echo '' && mkdir -p $TEST_PROJECT/.test-results && echo passed > $TEST_PROJECT/.test-results/001-test-feature.passed && echo '--- With .test-results/001-test-feature.passed ---' && echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr merge --squash\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_e2e-merge-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); if(r&&r.decision==='block'){console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED');}\""

# --- Evidence 9: workflow-gate ---
WORKFLOW_JS="$HOME/.claude/shtd-flow/lib/workflow.js"
mkdir -p "$TEST_PROJECT/workflows"
cat > "$TEST_PROJECT/workflows/test-pipeline.yml" << 'YAML'
name: test-pipeline
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
YAML

# Init workflow state
node -e "const wf=require('$WORKFLOW_JS'); wf.initState('test-pipeline','$TEST_PROJECT/workflows/test-pipeline.yml','$TEST_PROJECT');"

capture "09-workflow-gate" "workflow-gate: Enforces step order" \
  "cd $TEST_PROJECT && echo '=== workflow-gate: Step order enforcement ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo '' && echo 'Active workflow: test-pipeline' && echo 'Steps: build → test → deploy' && node -e \"const wf=require('$WORKFLOW_JS'); console.log('Current step:', wf.currentStep('$TEST_PROJECT')); wf.completeStep('build','$TEST_PROJECT'); console.log('After completing build, current step:', wf.currentStep('$TEST_PROJECT'));\" && echo '' && echo '--- Write during test step (build done, test gate satisfied) ---' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TEST_PROJECT/deploy.sh\",\"content\":\"deploy\"}}' | node -e \"process.env.CLAUDE_PROJECT_DIR='$TEST_PROJECT'; const m=require('$HOOKS_DIR/shtd_workflow-gate.js'); const i=JSON.parse(require('fs').readFileSync(0,'utf-8')); const r=m(i); if(r&&r.decision==='block'){console.log('✗ BLOCKED: '+r.reason);}else{console.log('✓ ALLOWED (gate satisfied)');}\""

# --- Evidence 10: audit log ---
capture "10-audit-log" "Audit log: Event capture proof" \
  "echo '=== SHTD Audit Log ===' && echo 'Host: '\$(hostname)' | IP: '\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null) && echo 'Date: '\$(date -u) && echo '' && echo 'Audit file: $HOME/.claude/shtd-flow/audit.jsonl' && echo 'Events:' && cat $HOME/.claude/shtd-flow/audit.jsonl 2>/dev/null | python3 -m json.tool 2>/dev/null || cat $HOME/.claude/shtd-flow/audit.jsonl 2>/dev/null || echo '(no events yet)' && echo '' && echo 'Total events:' && wc -l $HOME/.claude/shtd-flow/audit.jsonl 2>/dev/null || echo 0"

# Cleanup
kill $XVFB_PID 2>/dev/null || true
rm -f "$TEST_PROJECT/.shtd-workflow-state.json"

echo ""
echo "=========================================="
echo "  Screenshot capture complete — ${MODE}"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Screenshots saved to: $EVIDENCE_DIR"
echo "=========================================="
ls -la "$EVIDENCE_DIR"
