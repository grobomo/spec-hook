# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Status: Complete

## Session Handoff

User requested new project: **ccc-central** — Central monitoring dispatcher for Claude Code.
- Created `~/Documents/ProjectsCL1/ccc-central/TODO.md` with architecture and tasks
- Next: start new session in ccc-central project directory
- Spec-hook is fully complete (T001-T027, 5 PRs merged, real evidence report)

## Completed

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
