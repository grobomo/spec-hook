// WHY: Batched PRs with multiple tasks made mobile monitoring and rollbacks impossible.
// SHTD Flow module: shtd_pr-per-task-gate
// ENFORCES: Step 7 — one PR per task, task ID in title.

module.exports = function(input) {
  const tool = input?.tool_name;
  if (tool !== 'Bash') return null;

  const cmd = input?.tool_input?.command || '';
  if (!cmd.includes('gh pr create')) return null;

  // Check title includes task ID (T001, T002, etc.)
  const titleMatch = cmd.match(/--title\s+["']([^"']+)["']/);
  if (titleMatch) {
    const title = titleMatch[1];
    if (!/T\d+/i.test(title)) {
      return {
        decision: 'block',
        reason: '[shtd] PR title must include task ID (e.g. "T001: Add config parser"). One PR per task.'
      };
    }
  }

  return null;
};
