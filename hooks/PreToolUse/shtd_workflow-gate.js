// WHY: Steps in a workflow were skipped — build ran before setup, deploy before test.
// SHTD Flow module: shtd_workflow-gate
// ENFORCES: Workflow step order. If an active workflow exists, the current step's
// gate must be satisfied before code edits proceed.

const path = require('path');

function getWorkflow() {
  const candidates = [
    path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude', 'shtd-flow', 'lib', 'workflow.js'),
    path.join(__dirname, '..', '..', 'lib', 'workflow.js'),
  ];
  for (const c of candidates) {
    try { return require(c); } catch(e) {}
  }
  return null;
}

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Always allow: specs, tests, config, docs, workflow definitions
  const allowed = [
    /specs\//i, /test/i, /TODO\.md/i, /CLAUDE\.md/i, /SESSION_STATE/i,
    /\.claude\//i, /rules\//i, /\.github\//i, /config/i, /\.gitignore/i,
    /package\.json/i, /install/i, /setup/i, /archive\//i, /workflows\//i,
    /\.shtd-workflow/i,
  ];
  if (allowed.some(r => r.test(filePath))) return null;

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
      blocked: true,
      reason: `[shtd] Workflow "${state.workflow}" step "${current}" blocked: ${reasons}`
    };
  }

  return null;
};
