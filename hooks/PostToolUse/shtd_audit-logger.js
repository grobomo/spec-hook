// WHY: No unified timeline of workflow events — each step logged independently.
// SHTD Flow module: shtd_audit-logger
// Logs workflow-significant events to ~/.claude/shtd-flow/audit.jsonl

const path = require('path');
const getAudit = require(path.join(__dirname, '..', '..', 'lib', 'get-audit.js'));

module.exports = function(input) {
  const tool = input?.tool_name;
  const cmd = input?.tool_input?.command || '';
  const filePath = input?.tool_input?.file_path || '';
  const audit = getAudit();

  // Detect workflow events from tool usage patterns
  if (tool === 'Write' || tool === 'Edit') {
    if (/specs\/.*spec\.md/i.test(filePath)) {
      audit.logEvent('spec_created', { file: path.basename(filePath) });
    } else if (/specs\/.*tasks\.md/i.test(filePath)) {
      audit.logEvent('tasks_defined', { file: path.basename(filePath) });
    } else if (/test/i.test(filePath) && !/node_modules/.test(filePath)) {
      audit.logEvent('test_created', { file: path.basename(filePath) });
    }
  }

  if (tool === 'Bash') {
    if (cmd.includes('git checkout -b')) {
      const m = cmd.match(/checkout\s+-b\s+(\S+)/);
      if (m) audit.logEvent('branch_created', { branch: m[1] });
    }
    if (cmd.includes('gh pr create')) {
      const titleMatch = cmd.match(/--title\s+["']([^"']+)["']/);
      audit.logEvent('pr_opened', { title: titleMatch ? titleMatch[1] : 'unknown' });
    }
    if (cmd.includes('gh pr merge')) {
      audit.logEvent('pr_merged', { detail: cmd.slice(0, 100) });
    }
    if (cmd.includes('git push')) {
      audit.logEvent('code_pushed', { detail: cmd.slice(0, 80) });
    }
    // E2E test results
    if (/e2e.*pass/i.test(cmd) || /\.passed/.test(cmd)) {
      audit.logEvent('e2e_passed');
    }
  }

  return null; // PostToolUse modules don't block
};
