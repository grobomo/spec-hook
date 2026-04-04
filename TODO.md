# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Status: Complete

All tasks done. 12-page evidence PDF with real worker screenshots.

## Completed

- [x] T001-T021 (all core tasks — see git log)
- [x] T022 Initial evidence report (PDF with tables, user rejected — needs real screenshots)
- [x] Global MCP config — mcp-manager added to ~/.claude.json with `claude mcp add -s user`
- [x] T023 Evidence report with REAL screenshots + critical bug fix
  - **Critical bug found and fixed**: All 10 hook modules used `{ blocked: true }` return format,
    but hook-runner expects `{ decision: 'block' }`. Hooks were silently not blocking in production.
    Fixed all modules to use correct `decision: 'block'` format. Updated tests to match.
  - Deployed fixed hooks to Worker 1 via scripts/deploy-to-worker.sh
  - Captured 5 live evidence scenarios from EC2 Worker 1 (Docker container):
    1. install.sh --check — all 16 components verified OK
    2. branch-gate BLOCKS Write on master — returns JSON decision:block
    3. spec-gate BLOCKS Write without specs/ — returns JSON decision:block
    4. All gates PASS with proper setup (feature branch + specs + tracking)
    5. remote-tracking-gate BLOCKS untracked branch
  - Desktop screenshots with taskbar clock (evidence-terminal.png, e2e-local-tests.png)
  - 28/28 local e2e tests pass with new decision format
  - 12-page PDF: reports/shtd_flow_evidence_20260403_205805.pdf

## Scripts Created

- `scripts/capture-evidence.sh` — Run real hook modules on worker containers, capture output
- `scripts/deploy-to-worker.sh` — Deploy SHTD to worker Docker containers
- `scripts/check-worker-install.sh` — Verify SHTD installation on workers
- `scripts/take-screenshot.sh` — Desktop/command/remote screenshot tool (Python PIL)
- `scripts/generate-evidence-report.py` — Generate 12-page PDF with pm-report skill
