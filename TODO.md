# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Session State

- On branch: main (all merged)
- Pushed to grobomo/spec-hook (public)
- E2E proof test (28 tests) passes locally — all 9 gates covered
- Remote install test (14 tests) passes on ccc-worker-5 (Docker container)
- ccc-worker-5 stopped after testing

## Completed

- [x] T001 Create lib/audit.js — unified JSONL audit log
- [x] T002 Create lib/task_claims.py — multi-tab negotiation with OS locking
- [x] T003 Create hooks — all PreToolUse/PostToolUse/Stop modules
- [x] T004 Create install.sh — cross-platform setup (Windows/Mac/Linux)
- [x] T005 Create rules, CLAUDE.md, status CLI, secret-scan CI, .gitignore
- [x] T006 Workflow engine (lib/workflow.js) — YAML parser, state manager, step validator
- [x] T007 Workflow gate hook (shtd_workflow-gate.js) — enforce step order
- [x] T008 Workflow CLI (shtd-workflow.sh) — start/status/complete/reset
- [x] T009 First workflow: test-claude-install with step scripts
- [x] T010 Update installer and CLAUDE.md for workflow engine
- [x] T011 Run test-claude-install workflow on EC2 — validate full pipeline
- [x] T012 Merge feature branches to main, push to grobomo/spec-hook
- [x] T013 README.md with install instructions (merged to main)
- [x] T014 E2E proof test — 28 tests proving real-world hook behavior (all 9 gates)
- [x] T015 Code review: DRY up getAudit() helper — extracted to lib/get-audit.js
- [x] T016 Code review: DRY up allowed-path patterns — extracted to lib/allowed-paths.js
- [x] T017 YAML parser hardening — 12 edge case tests, all passed, added id filter
- [x] T018 Add e2e-merge-gate and remote-tracking-gate to e2e proof test

## Remaining

- [ ] T019 Create golden AMI from ccc-worker-5 with SHTD pre-installed (snapshot step of test-claude-install workflow)
- [ ] T020 Install SHTD on all running CCC workers (workers 1-4), not just worker-5
