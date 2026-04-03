# TODO — SHTD Flow (Spec-Hook-Test-Driven)

## What

Portable, installable workflow enforcement system for Claude Code. One setup script installs the entire spec→hook→test→PR pipeline with full audit trail.

## Why

Multiple Claude tabs duplicate work. Workflow steps are partially enforced. No unified audit log. Setup on new machines is manual. This project packages everything into `bash install.sh` and makes the workflow fully enforced end-to-end.

## Architecture

```
spec-hook/                    # grobomo/spec-hook (PUBLIC repo)
├── install.sh                # One-command setup for any Claude Code install
├── lib/
│   ├── audit.js              # Unified JSONL audit log
│   └── task_claims.py        # Multi-tab atomic task negotiation
├── hooks/
│   ├── PreToolUse/
│   │   ├── spec-gate.js      # Block code without specs/
│   │   ├── test-first-gate.js    # Block implementation before test exists
│   │   ├── branch-gate.js        # Block code on main
│   │   ├── pr-per-task-gate.js   # Block batched PRs
│   │   ├── e2e-merge-gate.js     # Block feature merge without E2E
│   │   └── secret-scan-gate.js   # Block push without scan
│   ├── PostToolUse/
│   │   └── audit-logger.js       # Log all workflow events
│   ├── SessionStart/
│   │   └── task-claim.js         # Claim next task at session start
│   └── Stop/
│       └── task-release.js       # Release claim on session end
├── rules/
│   └── shtd-flow.md              # Workflow rules injected at session start
├── scripts/
│   └── shtd-status.sh            # CLI: show workflow status for a project
└── .github/
    ├── publish.json
    └── workflows/secret-scan.yml
```

## Tasks

- [ ] T001 Create lib/audit.js — unified JSONL audit log
- [ ] T002 Create lib/task_claims.py — multi-tab negotiation with OS locking
- [ ] T003 Create hooks — all PreToolUse/PostToolUse/SessionStart/Stop modules
- [ ] T004 Create install.sh — cross-platform setup (Windows/Mac/Linux)
- [ ] T005 Create rules and CLAUDE.md
- [ ] T006 Test install on clean environment
- [ ] T007 Push to grobomo/spec-hook, publish as plugin
