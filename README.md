# spec-hook (SHTD Flow)

Spec-Hook-Test-Driven workflow enforcement for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One command installs the entire spec→hook→test→PR pipeline with full audit trail.

## What It Does

SHTD Flow enforces a disciplined development workflow through Claude Code hooks:

1. **Write specs first** — no code without a spec
2. **Write tests first** — no implementation without a test
3. **Feature branches** — no code on main
4. **One PR per task** — task ID required in PR title
5. **E2E before merge** — integration test evidence required
6. **Secret scan** — blocks push without CI scan
7. **Multi-tab negotiation** — auto-claims tasks, prevents duplicate work
8. **Enforceable workflows** — ordered step pipelines with gate conditions
9. **Full audit trail** — every workflow event logged to JSONL

## Install

Requires: [Node.js](https://nodejs.org/), [Python 3](https://python.org/), git

```bash
git clone https://github.com/grobomo/spec-hook.git
cd spec-hook
bash install.sh
```

The installer auto-bootstraps [hook-runner](https://github.com/grobomo/hook-runner) if not already installed.

### Verify

```bash
bash install.sh --check
```

### Uninstall

```bash
bash install.sh --uninstall
```

## Hook Modules

| Module | Enforces |
|--------|----------|
| `shtd_spec-gate` | Specs must exist before code edits |
| `shtd_test-first-gate` | Test file before implementation |
| `shtd_branch-gate` | No code on main branch |
| `shtd_pr-per-task-gate` | Task ID in PR title |
| `shtd_e2e-merge-gate` | E2E evidence before feature merge |
| `shtd_remote-tracking-gate` | Branch must track remote |
| `shtd_secret-scan-gate` | CI scan required for push |
| `shtd_task-claim` | Auto-claim tasks, prevent tab duplication |
| `shtd_workflow-gate` | Enforce workflow step order |
| `shtd_audit-logger` | Log all workflow events |
| `shtd_task-release` | Release task claim on exit |

## Workflows

Workflows are enforceable step pipelines defined in YAML. Unlike Claude Code skills (advisory), workflows block out-of-order work.

```bash
# List available workflows
bash ~/.claude/shtd-flow/scripts/shtd-workflow.sh list

# Start a workflow
bash ~/.claude/shtd-flow/scripts/shtd-workflow.sh start <name>

# Check current step
bash ~/.claude/shtd-flow/scripts/shtd-workflow.sh status

# Mark step complete
bash ~/.claude/shtd-flow/scripts/shtd-workflow.sh complete <step-id>
```

### Define Custom Workflows

Add YAML files to `workflows/` in your project or `~/.claude/shtd-flow/workflows/` globally:

```yaml
name: deploy-pipeline
steps:
  - id: build
    name: Build artifacts
    gate:
      require_files: []
    completion:
      require_files: ["dist/bundle.js"]
  - id: test
    name: Run tests
    gate:
      require_step: build
    completion:
      require_files: [".test-results/e2e.passed"]
  - id: deploy
    name: Deploy to production
    gate:
      require_step: test
    completion:
      require_files: ["deploy-receipt.txt"]
```

### Workflow Templates

Pre-built workflows for common project types in `workflows/templates/`:

| Template | Use Case |
|----------|----------|
| `api-wrapper.yml` | REST API client library (auth, endpoints, tests, docs) |
| `k8s-service.yml` | Containerized K8s service (Dockerfile, manifests, CI) |
| `cli-tool.yml` | Command-line tool (arg parsing, output, tests, packaging) |
| `project-onboarding.yml` | Bootstrap new project (git, CI, publish.json, first spec) |

```bash
# Start from a template
cp workflows/templates/api-wrapper.yml workflows/my-api.yml
bash ~/.claude/shtd-flow/scripts/shtd-workflow.sh start my-api
```

## Multi-Tab Task Negotiation

When multiple Claude Code sessions work on the same project:

- Each session auto-claims the next unchecked task from TODO.md
- Other sessions see the claim and work on different tasks
- Claims auto-release when sessions end or processes die
- Dead session cleanup via PID checking

```bash
# Check claim status
python ~/.claude/shtd-flow/lib/task_claims.py status --project-dir .
```

## Distributed Task Coordination (S3)

For fleet scenarios with multiple machines, `distributed_claims.py` extends local claims with:

- **S3-based locking** — claims stored in S3, visible to all instances
- **Spec claims** — claim exclusive spec generation rights for a feature
- **Race detection** — detects when two instances claim the same task within a configurable window
- **Heartbeat/lease expiry** — stale claims auto-release after timeout (default 10min)
- **Metrics** — contention rate, task completion time, per-instance activity

```bash
export SHTD_S3_BUCKET=my-bucket
export SHTD_INSTANCE_ID=worker-1

# Claim a task
python lib/distributed_claims.py claim T001 --project my-project --session abc123

# Claim spec generation rights
python lib/distributed_claims.py spec-claim 042-feature --project my-project --session abc123

# Refresh heartbeat (run every few minutes)
python lib/distributed_claims.py heartbeat --project my-project

# View all claims and instances
python lib/distributed_claims.py status --project my-project

# View coordination metrics
python lib/distributed_claims.py metrics --project my-project
```

Requires `boto3` and AWS credentials with S3 read/write access.

## Audit Log

All workflow events are logged to `~/.claude/shtd-flow/audit.jsonl`:

```bash
bash ~/.claude/shtd-flow/scripts/shtd-status.sh /path/to/project
```

## Cross-Platform

Tested on:
- Windows (Git Bash)
- Linux (Ubuntu, Docker containers)
- CCC worker instances (Docker + native)

## License

MIT
