# Tasks: 005 — Add Workflows to Hook-Runner

## Phase 1: Spec & Plan (spec-hook)
- [x] T001 Write spec, workflow YAML, and tasks for this feature
  **Checkpoint**: `bash scripts/test/test-T001-workflow-spec.sh`

## Phase 2: Build in hook-runner
- [ ] T002 Port workflow.js to hook-runner (extract from spec-hook, zero deps)
  **Checkpoint**: `bash scripts/test/test-T002-hookrunner-engine.sh`
- [ ] T003 Add workflow-gate PreToolUse module to hook-runner catalog
  **Checkpoint**: `bash scripts/test/test-T003-hookrunner-gate.sh`
- [ ] T004 Add --workflow CLI commands to setup.js (list, start, status, complete, reset)
  **Checkpoint**: `bash scripts/test/test-T004-hookrunner-cli.sh`
- [ ] T005 Add built-in workflow templates (enforce-shtd.yml, cross-project-reset.yml)
  **Checkpoint**: `bash scripts/test/test-T005-workflow-templates.sh`
- [ ] T006 Tests for workflow engine + gate + CLI
  **Checkpoint**: `bash scripts/test/test-T006-hookrunner-e2e.sh`

## Phase 3: Meta-workflow & SHTD update
- [ ] T007 Create enforce-shtd.yml meta-workflow (enforces using SHTD to create rules)
  **Checkpoint**: `bash scripts/test/test-T007-enforce-shtd.sh`
- [ ] T008 Update spec-hook to delegate to hook-runner's workflow engine
  **Checkpoint**: `bash scripts/test/test-T008-shtd-delegation.sh`
- [ ] T009 PR for hook-runner, PR for spec-hook, update docs
  **Checkpoint**: `bash scripts/test/test-T009-final-verify.sh`
