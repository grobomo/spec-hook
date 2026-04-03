// Shared helper: resolve audit.js from install location or repo-relative path.
// Used by all hook modules that need to log audit events.
// Falls back to a no-op logger if audit.js can't be found.

const path = require('path');

function getAudit() {
  const candidates = [
    path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude', 'shtd-flow', 'lib', 'audit.js'),
    path.join(__dirname, 'audit.js'),
  ];
  for (const c of candidates) {
    try { return require(c); } catch(e) {}
  }
  return { logEvent: () => {} };
}

module.exports = getAudit;
