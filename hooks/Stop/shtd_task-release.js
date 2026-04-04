// WHY: Claimed tasks stayed locked when sessions ended without releasing.
// SHTD Flow module: shtd_task-release
// Releases task claim on session stop. (PID check also handles crash recovery.)

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

module.exports = function(input) {
  const projectDir = process.env.CLAUDE_PROJECT_DIR;
  if (!projectDir) return null;

  const sessionId = process.env.CLAUDE_SESSION_ID
    || process.env.CLAUDE_CONVERSATION_ID || '';

  const script = path.join(__dirname, '..', '..', 'lib', 'task_claims.py');
  try { fs.accessSync(script); } catch(e) { return null; }

  // Find which task this session claimed
  try {
    const statusOut = execSync(
      `python "${script}" status --project-dir "${projectDir}"`,
      { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
    ).trim();
    const status = JSON.parse(statusOut);
    const sid12 = sessionId.slice(0, 12);

    for (const [task, claim] of Object.entries(status.claims || {})) {
      if (claim.session === sid12) {
        execSync(
          `python "${script}" release ${task} --session "${sessionId}" --project-dir "${projectDir}"`,
          { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
        );
      }
    }
  } catch(e) {
    // Don't block session stop
  }

  return null;
};
