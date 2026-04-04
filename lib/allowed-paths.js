// Shared allowed-path patterns for SHTD gate hooks.
// Gates that check Write/Edit operations skip files matching these patterns.
// Each gate can extend with gate-specific extras.

const BASE = [
  /TODO\.md/i, /CLAUDE\.md/i, /SESSION_STATE/i, /\.claude\//i,
  /rules\//i, /\.github\//i, /\.gitignore/i, /archive\//i,
];

const CODE_INFRA = [
  /specs\//i, /test/i, /config/i, /package\.json/i, /install/i, /setup/i,
];

// isAllowed(filePath, ...extraPatterns) — returns true if filePath matches
// base patterns or any extra patterns provided by the caller.
function isAllowed(filePath, ...extras) {
  const all = [...BASE, ...extras];
  return all.some(r => r.test(filePath));
}

module.exports = { BASE, CODE_INFRA, isAllowed };
