#!/usr/bin/env bash
# SHTD Workflow CLI — Manage enforceable workflows
#
# Usage:
#   bash shtd-workflow.sh list [project-dir]
#   bash shtd-workflow.sh start <workflow-name> [project-dir]
#   bash shtd-workflow.sh status [project-dir]
#   bash shtd-workflow.sh complete <step-id> [project-dir]
#   bash shtd-workflow.sh reset [project-dir]

set -euo pipefail

to_node() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

CMD="${1:-help}"
shift || true

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Resolve workflow.js path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATES=(
  "$SCRIPT_DIR/../lib/workflow.js"
  "$HOME/.claude/shtd-flow/lib/workflow.js"
)
WF_JS=""
for c in "${CANDIDATES[@]}"; do
  if [ -f "$c" ]; then WF_JS=$(to_node "$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"); break; fi
done
if [ -z "$WF_JS" ]; then echo -e "${RED}workflow.js not found${NC}"; exit 1; fi

case "$CMD" in
  list)
    PROJECT_DIR="${1:-.}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    NP=$(to_node "$PROJECT_DIR")
    node -e "
      const wf = require('${WF_JS}');
      const workflows = wf.findWorkflows('${NP}');
      if (workflows.length === 0) { console.log('No workflows found.'); process.exit(0); }
      for (const w of workflows) {
        console.log(w.name + ' (' + w.steps.length + ' steps) — ' + w.description);
        for (const s of w.steps) console.log('  ' + s.id + ': ' + s.name);
      }
    "
    ;;

  start)
    WF_NAME="${1:?Usage: shtd-workflow.sh start <name> [project-dir]}"
    PROJECT_DIR="${2:-.}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    NP=$(to_node "$PROJECT_DIR")
    node -e "
      const wf = require('${WF_JS}');
      const workflows = wf.findWorkflows('${NP}');
      const target = workflows.find(w => w.name === '${WF_NAME}');
      if (!target) { console.error('Workflow not found: ${WF_NAME}'); process.exit(1); }
      const existing = wf.readState('${NP}');
      if (existing) { console.error('Workflow \"' + existing.workflow + '\" already active. Reset first.'); process.exit(1); }
      wf.initState('${WF_NAME}', target._path, '${NP}');
      const current = wf.currentStep('${NP}');
      console.log('Workflow \"${WF_NAME}\" started. Current step: ' + current);
    "
    ;;

  status)
    PROJECT_DIR="${1:-.}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    NP=$(to_node "$PROJECT_DIR")
    node -e "
      const wf = require('${WF_JS}');
      const state = wf.readState('${NP}');
      if (!state) { console.log('No active workflow.'); process.exit(0); }
      console.log('Workflow: ' + state.workflow);
      console.log('Started:  ' + state.started_at);
      console.log('');
      const def = wf.loadWorkflow(state.workflow_path);
      const current = wf.currentStep('${NP}');
      for (const step of def.steps) {
        const s = state.steps[step.id] || {};
        let marker = '  ';
        if (s.status === 'completed') marker = 'OK';
        else if (step.id === current) marker = '>>';
        else marker = '  ';
        const status = s.status || 'pending';
        console.log(marker + ' ' + step.id.padEnd(20) + status.padEnd(14) + step.name);
      }
    "
    ;;

  complete)
    STEP_ID="${1:?Usage: shtd-workflow.sh complete <step-id> [project-dir]}"
    PROJECT_DIR="${2:-.}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    NP=$(to_node "$PROJECT_DIR")
    node -e "
      const wf = require('${WF_JS}');
      const state = wf.readState('${NP}');
      if (!state) { console.error('No active workflow.'); process.exit(1); }
      wf.completeStep('${STEP_ID}', '${NP}');
      const next = wf.currentStep('${NP}');
      console.log('Step \"${STEP_ID}\" completed.' + (next ? ' Next: ' + next : ' Workflow done!'));
    "
    ;;

  reset)
    PROJECT_DIR="${1:-.}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    STATE_FILE="$PROJECT_DIR/.shtd-workflow-state.json"
    if [ -f "$STATE_FILE" ]; then
      rm -f "$STATE_FILE"
      echo "Workflow state cleared."
    else
      echo "No active workflow to reset."
    fi
    ;;

  help|*)
    echo "SHTD Workflow CLI"
    echo ""
    echo "Usage:"
    echo "  shtd-workflow.sh list [project-dir]              List available workflows"
    echo "  shtd-workflow.sh start <name> [project-dir]      Start a workflow"
    echo "  shtd-workflow.sh status [project-dir]            Show current step"
    echo "  shtd-workflow.sh complete <step> [project-dir]   Mark step done"
    echo "  shtd-workflow.sh reset [project-dir]             Clear workflow state"
    ;;
esac
