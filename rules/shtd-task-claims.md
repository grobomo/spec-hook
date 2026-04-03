# SHTD Multi-Tab Task Negotiation

- Before first code edit, auto-claims next unchecked task from TODO.md (shtd_task-claim)
- Other tabs see the claim and pick a different task
- Claims auto-release when session ends or PID dies (shtd_task-release)
- Claim status: `python ~/.claude/shtd-flow/lib/task_claims.py status --project-dir .`
