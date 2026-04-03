// WHY: Claude implemented features nobody asked for, wasting hours.
// SHTD Flow module: shtd_spec-gate
// ENFORCES: Step 2 — specs must exist before code edits.

const fs = require('fs');
const path = require('path');
const getAudit = require(path.join(__dirname, '..', '..', 'lib', 'get-audit.js'));

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Allow: specs, TODO, CLAUDE.md, rules, tests, configs, dotfiles, install/setup
  const allowed = [
    /specs\//i, /TODO\.md/i, /CLAUDE\.md/i, /SESSION_STATE/i, /\.claude\//i,
    /rules\//i, /test/i, /\.github\//i, /config/i, /\.gitignore/i,
    /package\.json/i, /install/i, /setup/i, /archive\//i,
  ];
  if (allowed.some(r => r.test(filePath))) return null;

  const specsDir = path.join(projectDir, 'specs');
  if (!fs.existsSync(specsDir)) {
    getAudit().logEvent('code_blocked', { reason: 'no_specs_dir', file: path.basename(filePath) });
    return { blocked: true, reason: '[shtd] No specs/ directory. Create a spec first: specs/<NNN>-<feature>/spec.md' };
  }

  try {
    const specs = fs.readdirSync(specsDir).filter(f =>
      fs.statSync(path.join(specsDir, f)).isDirectory());
    if (specs.length === 0) {
      return { blocked: true, reason: '[shtd] specs/ is empty. Define at least one spec before writing code.' };
    }
  } catch(e) {}

  return null;
};
