// WHY: Feature branches were merged to main without integration testing.
// SHTD Flow module: shtd_e2e-merge-gate
// ENFORCES: Step 9 — feature branch merge to main requires E2E evidence.
// Only applies to merging feature branches (NNN-name), not task PRs.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const getAudit = require(path.join(__dirname, '..', '..', 'lib', 'get-audit.js'));

module.exports = function(input) {
  const tool = input?.tool_name;
  if (tool !== 'Bash') return null;

  const cmd = input?.tool_input?.command || '';

  // Only gate: gh pr merge into main, or git merge into main
  const isMergeToMain = cmd.includes('gh pr merge') ||
    (cmd.includes('git merge') && cmd.includes('main'));
  if (!isMergeToMain) return null;

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Determine which feature branch
  let branch;
  try {
    branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd: projectDir, encoding: 'utf-8', stdio: ['pipe','pipe','pipe']
    }).trim();
  } catch(e) { return null; }

  // Only enforce on feature branches (NNN-name pattern), not task branches (NNN-TNNN-slug)
  const isFeatureBranch = /^\d{3}-[a-z]/.test(branch) && !/T\d{3}/.test(branch);
  if (!isFeatureBranch) return null;

  // Check for E2E evidence: .test-results/<branch>.passed or .test-results/e2e.passed
  const resultsDir = path.join(projectDir, '.test-results');
  const markers = [
    path.join(resultsDir, `${branch}.passed`),
    path.join(resultsDir, 'e2e.passed'),
  ];

  if (!markers.some(m => fs.existsSync(m))) {
    getAudit().logEvent('merge_blocked', { reason: 'no_e2e', branch });
    return {
      decision: 'block',
      reason: `[shtd] Feature branch "${branch}" has no E2E test results. Run integration tests and create .test-results/${branch}.passed before merging to main.`
    };
  }

  return null;
};
