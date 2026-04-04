# 005: Add Workflows to Hook-Runner

## Problem

Spec-hook has a workflow engine (YAML step pipelines with gate enforcement) that only works within SHTD flow. The engine should be a hook-runner feature so any project can define workflows without depending on spec-hook. Currently:

- Workflow engine lives in `spec-hook/lib/workflow.js` — wrong home
- Workflow gate is an SHTD module — should be a hook-runner module
- No CLI integration in hook-runner (`--workflow` commands)
- No way to enforce "always use workflows" without manual discipline
- Cross-project context reset behavior needs workflow enforcement

## Solution

Move the workflow engine to hook-runner as a first-class feature:

1. **workflow.js** → hook-runner lib (zero-dep YAML parser + state machine)
2. **workflow-gate module** → hook-runner PreToolUse catalog
3. **CLI commands** → `node setup.js --workflow list|start|status|complete|reset`
4. **Global workflows** → `~/.claude/hooks/workflows/` (shared across projects)
5. **Project workflows** → `workflows/` in project root (project-specific)
6. **Meta-workflow** → `enforce-shtd.yml` that enforces SHTD pipeline using itself

## Architecture

```
hook-runner/
  workflow.js              # Engine: YAML parser, state machine, gate checker
  modules/PreToolUse/
    workflow-gate.js       # Gate: blocks out-of-order edits per active workflow
  workflows/               # Built-in workflow templates
    enforce-shtd.yml       # Meta: enforce spec→test→branch→PR pipeline
    cross-project-reset.yml # Context reset when switching projects
```

### Workflow Discovery (priority order)
1. Project: `$CLAUDE_PROJECT_DIR/workflows/*.yml`
2. Global: `~/.claude/hooks/workflows/*.yml`
3. Built-in: hook-runner `workflows/` directory

### State
- Per-project: `$CLAUDE_PROJECT_DIR/.workflow-state.json`
- Tracks: active workflow name, step statuses, timestamps

### Gate Logic
- On Write/Edit: check if active workflow exists → validate current step's gate
- Gates: `require_step` (previous step completed), `require_files` (files exist)
- Allowed paths bypass gates (TODO.md, CLAUDE.md, specs/, tests/, etc.)

## Cross-Project Context Reset Workflow

When TODO.md is complete and a new project is requested:
1. Save state to current project's TODO.md
2. Commit and push current project
3. Create TODO.md in new project (if needed)
4. Context reset into new project directory
5. Variables control behavior:
   - `PRESERVE_TAB=true` — keep old project tab open
   - `CONTINUE_BOTH=true` — work in both projects (no stop)
   - Default: stop old, start new

## Enforce-SHTD Meta-Workflow

A workflow that enforces "always use workflows when making behavioral rules":
1. Any new behavioral rule must start with a workflow YAML
2. The workflow defines enforcement steps
3. Only after workflow is active can gates/modules be created
4. Self-referential: this workflow enforces its own creation pattern

## Scope

- hook-runner gets: workflow.js, workflow-gate module, CLI commands, built-in templates
- spec-hook gets: updated to delegate to hook-runner's engine (thin wrapper)
- Both projects get PRs
