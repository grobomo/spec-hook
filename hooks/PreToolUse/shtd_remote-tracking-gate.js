// WHY: Commits on untracked branches were invisible on mobile.
// SHTD Flow module: shtd_remote-tracking-gate
// ENFORCES: Step 1 — branch must track a remote before code edits.

const { execSync } = require('child_process');

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';

  // Allow non-code files
  const allowed = [
    /TODO\.md/i, /CLAUDE\.md/i, /SESSION_STATE/i, /\.claude\//i, /rules\//i,
    /\.github\//i, /\.gitignore/i, /archive\//i, /specs\//i, /test/i,
  ];
  if (allowed.some(r => r.test(filePath))) return null;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  try {
    const branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd: projectDir, encoding: 'utf-8', stdio: ['pipe','pipe','pipe']
    }).trim();

    if (branch === 'main' || branch === 'master') return null; // main always tracks

    // Check if branch tracks a remote
    try {
      execSync(`git rev-parse --abbrev-ref ${branch}@{upstream}`, {
        cwd: projectDir, encoding: 'utf-8', stdio: ['pipe','pipe','pipe']
      });
    } catch(e) {
      return {
        blocked: true,
        reason: `[shtd] Branch "${branch}" doesn't track a remote. Run: git push -u origin ${branch}`
      };
    }
  } catch(e) {}

  return null;
};
