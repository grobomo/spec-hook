// SHTD Flow — Unified Audit Log
// Every workflow event → ~/.claude/shtd-flow/audit.jsonl
// Events: spec_created, tasks_defined, test_created, branch_created,
//         pr_opened, pr_merged, task_claimed, task_released,
//         e2e_passed, e2e_failed, code_blocked, merge_blocked

const fs = require('fs');
const path = require('path');
const os = require('os');

const FLOW_DIR = path.join(os.homedir(), '.claude', 'shtd-flow');
const AUDIT_FILE = path.join(FLOW_DIR, 'audit.jsonl');

function logEvent(event, data = {}) {
  try {
    fs.mkdirSync(FLOW_DIR, { recursive: true });
    const entry = {
      ts: new Date().toISOString(),
      event,
      project: data.project || path.basename(process.env.CLAUDE_PROJECT_DIR || process.cwd()),
      session: (process.env.CLAUDE_SESSION_ID || process.env.CLAUDE_CONVERSATION_ID || '').slice(0, 12),
      pid: process.pid,
      ...data,
    };
    // Remove undefined values
    for (const k of Object.keys(entry)) {
      if (entry[k] === undefined) delete entry[k];
    }
    fs.appendFileSync(AUDIT_FILE, JSON.stringify(entry) + '\n');
    return entry;
  } catch (e) {
    return null;
  }
}

function readEvents(project, limit = 200) {
  if (!fs.existsSync(AUDIT_FILE)) return [];
  const lines = fs.readFileSync(AUDIT_FILE, 'utf-8').trim().split('\n');
  const events = [];
  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      if (!project || entry.project === project) events.push(entry);
    } catch (e) { /* skip */ }
  }
  return events.slice(-limit);
}

function workflowStatus(projectDir) {
  const project = path.basename(projectDir);
  const events = readEvents(project);

  const tasks = {};
  for (const e of events) {
    const task = e.task || '_general';
    if (!tasks[task]) tasks[task] = [];
    tasks[task].push({ event: e.event, ts: e.ts, detail: e.detail || '' });
  }

  const phases = {};
  for (const [task, timeline] of Object.entries(tasks)) {
    const types = new Set(timeline.map(t => t.event));
    if (types.has('e2e_passed')) phases[task] = 'verified';
    else if (types.has('pr_merged')) phases[task] = 'merged';
    else if (types.has('pr_opened')) phases[task] = 'in review';
    else if (types.has('test_created')) phases[task] = 'implementing';
    else if (types.has('tasks_defined')) phases[task] = 'planned';
    else if (types.has('spec_created')) phases[task] = 'spec only';
    else phases[task] = 'active';
  }

  return { project, phases, total_events: events.length };
}

module.exports = { logEvent, readEvents, workflowStatus, FLOW_DIR, AUDIT_FILE };
