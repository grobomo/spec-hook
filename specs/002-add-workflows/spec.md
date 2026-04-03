# Spec 002: Enforceable Workflows

## What

Add a "workflow" primitive to SHTD flow. A workflow is a sequence of enforced steps — like a skill file, but with hook-backed gates that block out-of-order work. Skills are suggestions Claude can ignore. Workflows are mandatory pipelines.

## Why

Skills (`SKILL.md`) are instructions Claude reads but can skip. There's no enforcement. When a process matters (deploy sequence, test matrix, infra provisioning), you need the same hook-gate mechanism that SHTD uses for spec→test→PR, but configurable per-workflow instead of hardcoded.

## Design

### Workflow Definition File

```yaml
# workflows/test-claude-install.yml
name: test-claude-install
description: Spin up EC2, install Claude Code, test settings, create AMI
version: 1

steps:
  - id: provision
    name: Provision EC2 instance
    gate: # What must be true before this step runs
      require_files: []  # No prereqs for first step
    completion:
      require_files: ["instance-id.txt"]

  - id: install
    name: Install Claude Code + SHTD flow
    gate:
      require_files: ["instance-id.txt"]
      require_step: provision
    completion:
      require_files: ["install-verified.txt"]

  - id: test
    name: Run test suite
    gate:
      require_step: install
    completion:
      require_files: [".test-results/e2e.passed"]

  - id: snapshot
    name: Create AMI / golden image
    gate:
      require_step: test
    completion:
      require_files: ["ami-id.txt"]

  - id: cleanup
    name: Terminate instance
    gate:
      require_step: snapshot
    completion:
      audit_event: instance_terminated
```

### Where Workflows Live

- **Project-scoped**: `workflows/` directory in any project
- **Global**: `~/.claude/shtd-flow/workflows/` for cross-project workflows
- **Active workflow**: tracked in `.shtd-workflow-state.json` (gitignored)

### Enforcement Mechanism

One new PreToolUse hook: `shtd_workflow-gate.js`

1. Reads `workflows/*.yml` to find active workflows
2. Reads `.shtd-workflow-state.json` for current step progress
3. On code edit: checks if the edit maps to a step that has unmet gate conditions
4. Blocks with message: `[shtd] Workflow "X" step "Y" requires step "Z" to complete first`

### State File

```json
{
  "workflow": "test-claude-install",
  "started_at": "2026-04-03T12:00:00Z",
  "steps": {
    "provision": { "status": "completed", "completed_at": "..." },
    "install": { "status": "in_progress" },
    "test": { "status": "pending" },
    "snapshot": { "status": "pending" },
    "cleanup": { "status": "pending" }
  }
}
```

### CLI

```bash
# Start a workflow
bash scripts/shtd-workflow.sh start test-claude-install

# Check status
bash scripts/shtd-workflow.sh status

# Advance step (marks current complete, validates gates)
bash scripts/shtd-workflow.sh complete <step-id>

# Reset (restart from scratch)
bash scripts/shtd-workflow.sh reset
```

### Cross-Environment: Container vs Native

Workflows must work identically on:
- **Native Claude installs** (Windows/Mac/Linux with `~/.claude/`)
- **Docker containers** (CCC workers with mounted volumes)

The key: all paths use `$HOME/.claude/` which resolves correctly in both. Workflow state files are project-local (`.shtd-workflow-state.json`), so they travel with the repo. The hooks are installed globally via `install.sh`.

### Relationship to Skills

| | Skills | Workflows |
|---|---|---|
| File | `SKILL.md` (markdown) | `workflows/*.yml` (YAML) |
| Enforcement | Advisory (Claude reads) | Mandatory (hooks block) |
| Steps | Unordered suggestions | Ordered, gated pipeline |
| State | None | `.shtd-workflow-state.json` |
| Audit | None | Full JSONL audit trail |
| Scope | Per-skill | Per-project or global |

A workflow CAN reference a skill: "Step 3: follow the cloud-claude skill to provision." The workflow enforces the order; the skill provides the instructions for each step.
