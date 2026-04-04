// WHY: Claude implemented features nobody asked for, wasting hours.
// SHTD Flow module: shtd_spec-gate
// ENFORCES: Step 2 — specs must exist before code edits.

const fs = require('fs');
const path = require('path');
const getAudit = require(path.join(__dirname, '..', '..', 'lib', 'get-audit.js'));
const { isAllowed, CODE_INFRA } = require(path.join(__dirname, '..', '..', 'lib', 'allowed-paths.js'));

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  if (isAllowed(filePath, ...CODE_INFRA)) return null;

  const specsDir = path.join(projectDir, 'specs');
  if (!fs.existsSync(specsDir)) {
    getAudit().logEvent('code_blocked', { reason: 'no_specs_dir', file: path.basename(filePath) });
    return { decision: 'block', reason: '[shtd] No specs/ directory. Create a spec first: specs/<NNN>-<feature>/spec.md' };
  }

  try {
    const specs = fs.readdirSync(specsDir).filter(f =>
      fs.statSync(path.join(specsDir, f)).isDirectory());
    if (specs.length === 0) {
      return { decision: 'block', reason: '[shtd] specs/ is empty. Define at least one spec before writing code.' };
    }
  } catch(e) {}

  return null;
};
