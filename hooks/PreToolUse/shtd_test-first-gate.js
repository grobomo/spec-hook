// WHY: Implementation code was written before tests, making it impossible to
// verify the task was actually done vs. "it compiles so it works."
// SHTD Flow module: shtd_test-first-gate
// ENFORCES: Step 5 — test file must exist for a task before implementation code.

const fs = require('fs');
const path = require('path');

const getAudit = require(path.join(__dirname, '..', '..', 'lib', 'get-audit.js'));

function findCurrentTask(projectDir) {
  // Check task-claims first
  const claimsDir = path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude', 'shtd-flow', 'claims');
  const key = projectDir.replace(/[\\/]/g, '-').replace(/:/g, '').replace(/^-+|-+$/g, '');
  const claimsFile = path.join(claimsDir, `${key}.json`);
  if (fs.existsSync(claimsFile)) {
    try {
      const claims = JSON.parse(fs.readFileSync(claimsFile, 'utf-8'));
      const sid = (process.env.CLAUDE_SESSION_ID || process.env.CLAUDE_CONVERSATION_ID || '').slice(0, 12);
      for (const [task, claim] of Object.entries(claims)) {
        if (claim.session && claim.session.startsWith(sid)) return task;
      }
    } catch(e) {}
  }
  // Fallback: check git branch for TNNN pattern
  try {
    const { execSync } = require('child_process');
    const branch = execSync('git rev-parse --abbrev-ref HEAD', { cwd: projectDir, encoding: 'utf-8' }).trim();
    const m = branch.match(/T(\d+)/);
    if (m) return `T${m[1]}`;
  } catch(e) {}
  return null;
}

function testExistsForTask(projectDir, taskId) {
  // Look for test files: scripts/test/*taskId*, test/*taskId*, *.test.*
  const searchDirs = [
    path.join(projectDir, 'scripts', 'test'),
    path.join(projectDir, 'test'),
    path.join(projectDir, 'tests'),
    path.join(projectDir, 'scripts', 'tests'),
  ];
  const taskLower = taskId.toLowerCase();
  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir);
    if (files.some(f => f.toLowerCase().includes(taskLower))) return true;
  }
  // Also check .test-results/ for marker files
  const resultsDir = path.join(projectDir, '.test-results');
  if (fs.existsSync(resultsDir)) {
    const files = fs.readdirSync(resultsDir);
    if (files.some(f => f.toLowerCase().includes(taskLower))) return true;
  }
  return false;
}

module.exports = function(input) {
  const tool = input?.tool_name;
  if (!['Write', 'Edit'].includes(tool)) return null;

  const filePath = input?.tool_input?.file_path || input?.tool_input?.path || '';
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Allow: test files themselves, specs, config, docs
  const allowed = [
    /test/i, /spec/i, /TODO\.md/i, /CLAUDE\.md/i, /SESSION_STATE/i,
    /\.claude\//i, /rules\//i, /\.github\//i, /config/i, /\.gitignore/i,
    /package\.json/i, /install/i, /setup/i, /archive\//i,
  ];
  if (allowed.some(r => r.test(filePath))) return null;

  const taskId = findCurrentTask(projectDir);
  if (!taskId) return null; // No claimed task — can't enforce

  if (!testExistsForTask(projectDir, taskId)) {
    getAudit().logEvent('code_blocked', {
      reason: 'no_test_for_task', task: taskId, file: path.basename(filePath)
    });
    return {
      blocked: true,
      reason: `[shtd] Test-first: no test found for ${taskId}. Write a test in scripts/test/ or test/ before implementation code.`
    };
  }

  return null;
};
