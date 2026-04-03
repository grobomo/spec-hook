# Spec 001: Build SHTD Flow

## What
Portable, installable workflow enforcement system for Claude Code. One `bash install.sh` installs the entire spec→hook→test→PR pipeline with full audit trail.

## Why
Multiple Claude tabs duplicate work. Workflow steps are partially enforced. No unified audit log. Setup on new machines is manual. This project packages everything into a single install command.

## Scope
- Unified JSONL audit log (lib/audit.js)
- Multi-tab task negotiation with OS locking (lib/task_claims.py)
- 8 PreToolUse gates, 1 PostToolUse logger, 1 Stop handler
- Cross-platform installer (Windows/Mac/Linux)
- Rules file and CLAUDE.md for project docs
- Status CLI script
- GitHub CI (secret-scan.yml)
