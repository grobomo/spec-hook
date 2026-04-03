# spec-hook — SHTD Flow

Portable workflow enforcement for Claude Code. Installs spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Quick Start

```bash
# Prerequisite: hook-runner (grobomo/hook-runner)
bash install.sh          # Install
bash install.sh --check  # Verify
bash install.sh --uninstall  # Remove
```

## Architecture

- `lib/audit.js` — Unified JSONL audit log at `~/.claude/shtd-flow/audit.jsonl`
- `lib/task_claims.py` — Multi-tab task negotiation with OS file locking
- `lib/workflow.js` — Workflow engine: YAML parser, state manager, step gate validator
- `hooks/PreToolUse/` — Gate modules that block rule violations + task claim + workflow gates
- `hooks/PostToolUse/` — Audit logger for workflow events
- `hooks/Stop/` — Release task claim on exit
- `install.sh` — Cross-platform installer (copies to `~/.claude/`)

## Hook Modules

| Module | Event | Enforces |
|--------|-------|----------|
| shtd_spec-gate | PreToolUse | Specs must exist before code edits |
| shtd_test-first-gate | PreToolUse | Test file before implementation |
| shtd_branch-gate | PreToolUse | No code on main |
| shtd_pr-per-task-gate | PreToolUse | Task ID in PR title |
| shtd_e2e-merge-gate | PreToolUse | E2E evidence before feature merge |
| shtd_remote-tracking-gate | PreToolUse | Branch must track remote |
| shtd_secret-scan-gate | PreToolUse | secret-scan.yml required for push |
| shtd_task-claim | PreToolUse | Claim next task before code edit |
| shtd_workflow-gate | PreToolUse | Enforce workflow step order |
| shtd_audit-logger | PostToolUse | Log spec/test/branch/PR/push events |
| shtd_task-release | Stop | Release claimed task |

## Workflows

Workflows are enforceable step pipelines defined in YAML. Unlike skills (advisory), workflows block out-of-order work via hooks.

```bash
# List available workflows
bash scripts/shtd-workflow.sh list

# Start a workflow
bash scripts/shtd-workflow.sh start test-claude-install

# Check current step
bash scripts/shtd-workflow.sh status

# Mark step complete
bash scripts/shtd-workflow.sh complete <step-id>

# Reset workflow
bash scripts/shtd-workflow.sh reset
```

### Included Workflows

- **test-claude-install** — Provision EC2, install Claude+SHTD, test, create AMI, cleanup. Supports container and native modes via `INSTALL_MODE` env var.

### Creating Custom Workflows

Add YAML files to `workflows/` (project-scoped) or `~/.claude/shtd-flow/workflows/` (global).

```yaml
name: my-workflow
steps:
  - id: step1
    name: First step
    gate:
      require_files: []
    completion:
      require_files: ["step1-done.txt"]
  - id: step2
    name: Second step
    gate:
      require_step: step1
    completion:
      require_files: ["step2-done.txt"]
```

## Status CLI

```bash
bash scripts/shtd-status.sh /path/to/project
```
