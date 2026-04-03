# SHTD Flow — Spec-Hook-Test-Driven Workflow

## The Pipeline

1. **Create repo** with remote tracking (shtd_remote-tracking-gate)
2. **Write specs** in specs/<NNN>-<feature>/spec.md (shtd_spec-gate)
3. **Break into tasks** in specs/<NNN>-<feature>/tasks.md
4. **Define completion criteria** per task (testable, automatable)
5. **Write failing tests** before implementation (shtd_test-first-gate)
6. **Feature branch** — never code on main (shtd_branch-gate)
7. **PR per task** with task ID in title (shtd_pr-per-task-gate)
8. **Tests pass** before PR close
9. **E2E integration test** before merging feature to main (shtd_e2e-merge-gate)
10. **Secret scan** before push (shtd_secret-scan-gate)

## Multi-Tab Negotiation

- Session start auto-claims next unchecked task from TODO.md (shtd_task-claim)
- Other tabs see the claim and pick a different task
- Claims auto-release when session ends or PID dies (shtd_task-release)
- Claim status: `python ~/.claude/shtd-flow/lib/task_claims.py status --project-dir .`

## Audit Log

All workflow events logged to: `~/.claude/shtd-flow/audit.jsonl`
- spec_created, tasks_defined, test_created, branch_created
- pr_opened, pr_merged, code_pushed
- task_claimed, task_released, auto_release
- code_blocked, merge_blocked, e2e_passed, e2e_failed
