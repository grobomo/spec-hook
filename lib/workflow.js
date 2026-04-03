// SHTD Flow — Workflow Engine
// Loads YAML workflow definitions, manages step state, validates gates.
// Works on both native Claude installs and Docker containers.

const fs = require('fs');
const path = require('path');

const STATE_FILE = '.shtd-workflow-state.json';

// --- YAML Parser (minimal, no deps) ---
// Handles the subset of YAML used in workflow definitions:
// top-level scalars, step arrays with nested objects, string arrays

function parseYaml(text) {
  const result = {};
  const lines = text.split('\n');
  let i = 0;
  let currentArray = null;
  let currentArrayKey = null;
  let currentObj = null;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trimEnd();

    // Skip empty lines and comments
    if (!trimmed || trimmed.startsWith('#')) { i++; continue; }

    const indent = line.length - line.trimStart().length;

    // Top-level scalar: "key: value"
    if (indent === 0 && !trimmed.startsWith('-')) {
      const m = trimmed.match(/^(\w+):\s*(.*)/);
      if (m) {
        currentArray = null; currentArrayKey = null; currentObj = null;
        const val = m[2].trim();
        if (!val) {
          // Could be start of array or nested object
          currentArrayKey = m[1];
          result[m[1]] = [];
          currentArray = result[m[1]];
        } else {
          result[m[1]] = parseScalar(val);
        }
      }
      i++; continue;
    }

    // Array item: "  - id: value" or "  - value"
    if (trimmed.startsWith('- ') || (indent > 0 && trimmed.trimStart().startsWith('- '))) {
      const content = trimmed.trimStart().slice(2).trim();
      const kvMatch = content.match(/^(\w+):\s*(.*)/);
      if (kvMatch) {
        currentObj = {};
        currentObj[kvMatch[1]] = parseScalar(kvMatch[2]);
        if (currentArray) currentArray.push(currentObj);
      } else {
        // Simple array value
        if (currentArray) currentArray.push(parseScalar(content));
      }
      i++; continue;
    }

    // Nested key under array item
    if (indent > 0 && currentObj && !trimmed.trimStart().startsWith('-')) {
      const nested = trimmed.trim();
      const kvMatch = nested.match(/^(\w+):\s*(.*)/);
      if (kvMatch) {
        const key = kvMatch[1];
        const val = kvMatch[2].trim();
        if (!val) {
          // Sub-object (like gate: or completion:)
          const subObj = {};
          const parentIndent = indent;
          i++;
          let subBaseIndent = -1;
          while (i < lines.length) {
            const subLine = lines[i];
            const subTrimmed = subLine.trimEnd();
            if (!subTrimmed) { i++; continue; }
            const subIndent = subLine.length - subLine.trimStart().length;
            // First non-empty line sets the expected indent for sub-keys
            if (subBaseIndent === -1) subBaseIndent = subIndent;
            // If we've dedented back to parent level or less, stop
            if (subIndent < subBaseIndent) break;
            const subKv = subTrimmed.trim().match(/^(\w+):\s*(.*)/);
            if (subKv) {
              subObj[subKv[1]] = parseScalar(subKv[2]);
            }
            i++;
          }
          currentObj[key] = subObj;
          continue;
        } else {
          currentObj[key] = parseScalar(val);
        }
      }
      i++; continue;
    }

    i++;
  }

  return result;
}

function parseScalar(val) {
  if (!val || val === '~' || val === 'null') return null;
  if (val === 'true') return true;
  if (val === 'false') return false;
  if (/^\d+$/.test(val)) return parseInt(val, 10);
  // Quoted string
  if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
    return val.slice(1, -1);
  }
  // Inline array: ["a", "b"]
  if (val.startsWith('[') && val.endsWith(']')) {
    const inner = val.slice(1, -1).trim();
    if (!inner) return [];
    return inner.split(',').map(s => parseScalar(s.trim()));
  }
  return val;
}

// --- Workflow Loading ---

function loadWorkflow(yamlPath) {
  const text = fs.readFileSync(yamlPath, 'utf-8');
  const parsed = parseYaml(text);
  return {
    name: parsed.name || path.basename(yamlPath, '.yml'),
    description: parsed.description || '',
    version: parsed.version || 1,
    steps: (parsed.steps || []).map(s => ({
      id: s.id,
      name: s.name || s.id,
      gate: s.gate || {},
      completion: s.completion || {},
    })),
    _path: yamlPath,
  };
}

function findWorkflows(projectDir) {
  const dirs = [
    path.join(projectDir, 'workflows'),
    path.join(process.env.HOME || process.env.USERPROFILE || '', '.claude', 'shtd-flow', 'workflows'),
  ];
  const workflows = [];
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      if (f.endsWith('.yml') || f.endsWith('.yaml')) {
        try { workflows.push(loadWorkflow(path.join(dir, f))); } catch(e) {}
      }
    }
  }
  return workflows;
}

// --- State Management ---

function statePath(projectDir) {
  return path.join(projectDir, STATE_FILE);
}

function readState(projectDir) {
  const p = statePath(projectDir);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf-8')); } catch(e) { return null; }
}

function writeState(state, projectDir) {
  fs.writeFileSync(statePath(projectDir), JSON.stringify(state, null, 2) + '\n');
  return state;
}

function initState(workflowName, yamlPath, projectDir) {
  const def = loadWorkflow(yamlPath);
  const steps = {};
  for (const step of def.steps) {
    steps[step.id] = { status: 'pending' };
  }
  const state = {
    workflow: workflowName,
    workflow_path: yamlPath,
    started_at: new Date().toISOString(),
    steps,
  };
  return writeState(state, projectDir);
}

function completeStep(stepId, projectDir) {
  const state = readState(projectDir);
  if (!state) throw new Error('No active workflow');
  if (!state.steps[stepId]) throw new Error(`Unknown step: ${stepId}`);
  state.steps[stepId] = {
    status: 'completed',
    completed_at: new Date().toISOString(),
  };
  // Advance next pending step to in_progress
  const def = loadWorkflow(state.workflow_path);
  for (const step of def.steps) {
    if (state.steps[step.id]?.status === 'pending') {
      state.steps[step.id].status = 'in_progress';
      break;
    }
  }
  return writeState(state, projectDir);
}

function currentStep(projectDir) {
  const state = readState(projectDir);
  if (!state) return null;
  // First in_progress, or first pending
  const def = loadWorkflow(state.workflow_path);
  for (const step of def.steps) {
    const s = state.steps[step.id];
    if (s?.status === 'in_progress') return step.id;
  }
  for (const step of def.steps) {
    const s = state.steps[step.id];
    if (s?.status === 'pending') return step.id;
  }
  return null; // All done
}

// --- Gate Checking ---

function checkGate(stepId, projectDir) {
  const state = readState(projectDir);
  if (!state) return { allowed: true, reason: 'no active workflow' };

  const def = loadWorkflow(state.workflow_path);
  const stepDef = def.steps.find(s => s.id === stepId);
  if (!stepDef) return { allowed: true, reason: 'unknown step' };

  const gate = stepDef.gate;
  const reasons = [];

  // Check require_step
  if (gate.require_step) {
    const reqStatus = state.steps[gate.require_step];
    if (!reqStatus || reqStatus.status !== 'completed') {
      reasons.push(`Step "${gate.require_step}" not completed`);
    }
  }

  // Check require_files
  if (gate.require_files && Array.isArray(gate.require_files) && gate.require_files.length > 0) {
    for (const f of gate.require_files) {
      const fullPath = path.isAbsolute(f) ? f : path.join(projectDir, f);
      if (!fs.existsSync(fullPath)) {
        reasons.push(`Required file missing: ${f}`);
      }
    }
  }

  if (reasons.length > 0) {
    return { allowed: false, step: stepId, reasons };
  }
  return { allowed: true, step: stepId };
}

// Check if a file edit is allowed given the active workflow
function checkEditAllowed(filePath, projectDir) {
  const state = readState(projectDir);
  if (!state) return { allowed: true };

  const current = currentStep(projectDir);
  if (!current) return { allowed: true }; // All done

  // The edit is allowed if the current step's gate is satisfied
  const gateCheck = checkGate(current, projectDir);
  return gateCheck;
}

module.exports = {
  parseYaml,
  loadWorkflow,
  findWorkflows,
  readState,
  writeState,
  initState,
  completeStep,
  currentStep,
  checkGate,
  checkEditAllowed,
  STATE_FILE,
};
