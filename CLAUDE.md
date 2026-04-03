# spec-hook — SHTD Flow

Portable workflow enforcement for Claude Code. Installs spec→hook→test→PR pipeline with full audit trail.

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
- `hooks/PreToolUse/` — Gate modules that block rule violations + task claim
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
| shtd_audit-logger | PostToolUse | Log spec/test/branch/PR/push events |
| shtd_task-release | Stop | Release claimed task |

## Status CLI

```bash
bash scripts/shtd-status.sh /path/to/project
```
