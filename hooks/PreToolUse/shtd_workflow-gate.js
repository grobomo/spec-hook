// WHY: Steps in a workflow were skipped — build ran before setup, deploy before test.
// SHTD Flow module: shtd_workflow-gate
// ENFORCES: Workflow step order. If an active workflow exists, the current step's
// gate must be satisfied before code edits proceed.

const path = require('path');
const { isAllowed, CODE_INFRA } = require(path.join(__dirname, '..', '..', 'lib', 'allowed-paths.js'));

function getWorkflow() {
  try { return require(path.join(__dirname, '..', '..', 'lib', 'workflow.js')); } catch(e) {}
  return null;
}

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  if (isAllowed(filePath, ...CODE_INFRA, /workflows\//i, /\.shtd-workflow/i)) return null;

  const wf = getWorkflow();
  if (!wf) return null;

  const state = wf.readState(projectDir);
  if (!state) return null; // No active workflow

  const current = wf.currentStep(projectDir);
  if (!current) return null; // All steps done

  const check = wf.checkGate(current, projectDir);
  if (!check.allowed) {
    const reasons = (check.reasons || []).join('; ');
    return {
      decision: 'block',
      reason: `[shtd] Workflow "${state.workflow}" step "${current}" blocked: ${reasons}`
    };
  }

  return null;
};
