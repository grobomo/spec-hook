# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Status: Complete

All tasks done. Deployed to all 4 workers. 12-page evidence PDF.

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
