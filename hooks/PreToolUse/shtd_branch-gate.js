// WHY: Claude committed directly to main, bypassing review.
// SHTD Flow module: shtd_branch-gate
// ENFORCES: Step 6 — code edits must be on a feature/task branch, never main.

const { execSync } = require('child_process');
const path = require('path');
const { isAllowed } = require(path.join(__dirname, '..', '..', 'lib', 'allowed-paths.js'));

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  if (isAllowed(filePath)) return null;

  try {
    const branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd: projectDir, encoding: 'utf-8', stdio: ['pipe','pipe','pipe']
    }).trim();

    if (branch === 'main' || branch === 'master') {
      return {
        decision: 'block',
        reason: `[shtd] On ${branch} branch. Create a feature branch first: git checkout -b <NNN>-<feature-name>`
      };
    }
  } catch(e) {
    // Not a git repo or git not available — skip
  }

  return null;
};
