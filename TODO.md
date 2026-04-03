# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail. Includes enforceable workflows — ordered step pipelines backed by hooks.

## Tasks

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
- [ ] T013 Publish as installable plugin (README install instructions)
