// WHY: Multiple Claude tabs working on the same project duplicated effort.
// SHTD Flow module: shtd_task-claim
// Claims the next available task at session start. Other tabs get different tasks.

const { execSync } = require('child_process');
const path = require('path');

module.exports = function(input) {
  const projectDir = process.env.CLAUDE_PROJECT_DIR;
  if (!projectDir) return null;

  const sessionId = process.env.CLAUDE_SESSION_ID
    || process.env.CLAUDE_CONVERSATION_ID
    || require('crypto').randomUUID().slice(0, 12);

  // Find task_claims.py — installed location or repo location
  const candidates = [
    path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude', 'shtd-flow', 'lib', 'task_claims.py'),
    path.join(__dirname, '..', '..', 'lib', 'task_claims.py'),
  ];
  let script;
  for (const c of candidates) {
    try { require('fs').accessSync(c); script = c; break; } catch(e) {}
  }
  if (!script) return null;

  try {
    const result = execSync(
      `python "${script}" next --session "${sessionId}" --project-dir "${projectDir}"`,
      { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
    ).trim();

    const parsed = JSON.parse(result);

    if (parsed.next) {
      const cont = parsed.already_mine ? ' (continuing)' : '';
      return {
        text: `[shtd] Task claimed: ${parsed.next}${cont}. Other tabs will work on different tasks. Focus on ${parsed.next}.`
      };
    } else if (parsed.reason === 'all_claimed') {
      const summary = Object.entries(parsed.claimed || {}).map(([t, s]) => `${t}→${s}`).join(', ');
      return {
        text: `[shtd] All tasks claimed by other sessions (${summary}). Work on code review, docs, or optimization.`
      };
    }
    return null;
  } catch (e) {
    return null; // Don't block session start
  }
};
