// WHY: API keys were committed to git history and had to be rotated.
// SHTD Flow module: shtd_secret-scan-gate
// ENFORCES: Step 11 — block push without secret-scan.yml in the repo.

const fs = require('fs');
const path = require('path');

module.exports = function(input) {
  const tool = input?.tool_name;
  if (tool !== 'Bash') return null;

  const cmd = input?.tool_input?.command || '';
  if (!cmd.includes('git push')) return null;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const scanFile = path.join(projectDir, '.github', 'workflows', 'secret-scan.yml');

  if (!fs.existsSync(scanFile)) {
    return {
      decision: 'block',
      reason: '[shtd] No .github/workflows/secret-scan.yml. Add a secret scan CI workflow before pushing.'
    };
  }

  return null;
};
