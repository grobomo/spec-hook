// WHY: Multiple Claude tabs working on the same project duplicated effort.
// SessionStart only runs once, but sessions work on many tasks sequentially.
// SHTD Flow module: shtd_task-claim (PreToolUse)
// Before code edits, ensures this session has a claimed task.
// If no claim exists (first edit, or previous task completed), claims next available.
// Does NOT block — only informs Claude which task to focus on.

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// In-memory cache: avoid re-claiming on every tool call in the same process
let lastClaim = null;
let lastCheckTs = 0;
const CHECK_INTERVAL_MS = 30000; // Re-check every 30s at most

function findScript() {
  const p = path.join(__dirname, '..', '..', 'lib', 'task_claims.py');
  try { fs.accessSync(p); return p; } catch(e) { return null; }
}

module.exports = function(input) {
  const tool = input?.tool_name;
  // Only trigger on code-edit tools
  if (!['Write', 'Edit'].includes(tool)) return null;

  const projectDir = process.env.CLAUDE_PROJECT_DIR;
  if (!projectDir) return null;

  // Throttle: don't re-check on every single edit
  const now = Date.now();
  if (lastClaim && (now - lastCheckTs) < CHECK_INTERVAL_MS) return null;
  lastCheckTs = now;

  const sessionId = process.env.CLAUDE_SESSION_ID
    || process.env.CLAUDE_CONVERSATION_ID
    || require('crypto').randomUUID().slice(0, 12);

  const script = findScript();
  if (!script) return null;

  try {
    // Check current status first — do we already have a claim?
    const statusOut = execSync(
      `python "${script}" status --project-dir "${projectDir}"`,
      { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
    ).trim();
    const status = JSON.parse(statusOut);
    const sid12 = sessionId.slice(0, 12);

    // Already have a claim — check if that task is still unchecked
    for (const [task, claim] of Object.entries(status.claims || {})) {
      if (claim.session === sid12) {
        if (status.tasks?.includes(task)) {
          lastClaim = task;
          return null; // Still working on it, no message needed
        }
        // Task completed (no longer in unchecked list) — release and claim next
        execSync(
          `python "${script}" release ${task} --session "${sessionId}" --status completed --project-dir "${projectDir}"`,
          { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
        );
      }
    }

    // No current claim — claim next available
    const result = execSync(
      `python "${script}" next --session "${sessionId}" --project-dir "${projectDir}"`,
      { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] }
    ).trim();
    const parsed = JSON.parse(result);

    if (parsed.next) {
      lastClaim = parsed.next;
      const cont = parsed.already_mine ? ' (continuing)' : '';
      // Don't block, just inform
      return null;
    } else if (parsed.reason === 'all_claimed') {
      const summary = Object.entries(parsed.claimed || {}).map(([t, s]) => `${t}→${s}`).join(', ');
      return {
        blocked: true,
        reason: `[shtd] All tasks claimed by other sessions (${summary}). Work on code review, docs, or wait for a task to free up.`
      };
    }
    return null;
  } catch (e) {
    return null; // Don't block on claim errors
  }
};
