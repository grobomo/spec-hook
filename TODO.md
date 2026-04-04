# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Status: Complete

## Completed (005: Workflows in hook-runner)
- [x] T001 Spec and workflow YAML (PR #9)
- [x] T002 Port workflow.js to hook-runner (PR #10)
- [x] T003 Add workflow-gate PreToolUse module (PR #11)
- [x] T004 Add --workflow CLI commands (PR #12)
- [x] T005 Built-in templates: enforce-shtd.yml, cross-project-reset.yml (PR #13)
- [x] T006 E2E tests — 9/9 lifecycle assertions (PR #14)
- [x] T007 enforce-shtd meta-workflow — self-enforcing (PR #15)
- [x] T008 Delegation verification (PR #16)
- [x] T009 Final cross-project verification — 14/14 checks (PR #17)
- [x] Hook-runner PR: grobomo/hook-runner#66

## Completed (earlier)

- [x] T001-T021 (all core tasks — see git log)
- [x] T022 Initial evidence report (PDF with tables, user rejected — needs real screenshots)
- [x] Global MCP config — mcp-manager added to ~/.claude.json with `claude mcp add -s user`
- [x] T023 Fix hook decision format + real evidence report (PR #1)
  - Critical bug: all modules used `{blocked:true}` but hook-runner expects `{decision:'block'}`
  - 12-page PDF with 5 live evidence scenarios from EC2 Worker 1
- [x] T024 Deploy fixed hooks to all 4 CCC workers (PR #2)
- [x] T025 Tighten allowed-paths regex — `/test/i` was too broad (PR #3)
- [x] Reinstalled locally + redeployed T025 fix to all 4 workers
- [x] T026 Code review: DRY worker config, archive stale scripts, tighten audit regex (PR #4)
