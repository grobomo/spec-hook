# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Status: In Progress

## Active

- [x] T027 Fresh deployment evidence report (Linux EC2)
  - Provisioned fresh Ubuntu 22.04 EC2 (i-05bc762ad4d8c37fc, 3.129.204.76)
  - Installed xvfb + xterm + scrot for REAL screen captures
  - Phase A: Native — 10 real xterm screenshots, all hooks firing correctly
  - Phase B: Docker — 10 real xterm screenshots from inside container b4b099a6e5af
  - 15-page PDF: reports/shtd_flow_evidence_20260403_220200.pdf (776 KB)
  - EC2 terminated after evidence captured

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
