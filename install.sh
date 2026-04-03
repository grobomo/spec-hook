#!/usr/bin/env bash
# SHTD Flow Installer — Spec-Hook-Test-Driven workflow for Claude Code
#
# Prerequisites: hook-runner (grobomo/hook-runner) must be installed first.
# Hook-runner provides the run-modules/ system that SHTD modules plug into.
#
# Usage:
#   bash install.sh              # Install to ~/.claude/
#   bash install.sh --check      # Verify installation
#   bash install.sh --uninstall  # Remove SHTD modules (keeps hook-runner)
#
# What it installs:
#   ~/.claude/shtd-flow/lib/          audit.js, task_claims.py
#   ~/.claude/hooks/run-modules/*/    shtd_*.js modules (8 PreToolUse, 1 PostToolUse, 1 Stop)
#   ~/.claude/shtd-flow/rules/        shtd-flow.md workflow rules

set -euo pipefail

SHTD_HOME="${HOME}/.claude/shtd-flow"
HOOKS_BASE="${HOME}/.claude/hooks/run-modules"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors (if terminal supports them)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

check_prereqs() {
  local errors=0

  # Check hook-runner is installed
  if [ ! -f "${HOOKS_BASE}/../run-pretooluse.js" ] && [ ! -f "${HOOKS_BASE}/../run-PreToolUse.js" ]; then
    # Check for any run-*.js runner
    if ! ls "${HOME}/.claude/hooks/run-"*.js >/dev/null 2>&1; then
      fail "hook-runner not installed. Install from: grobomo/hook-runner"
      echo "  Hook-runner provides the run-modules/ system that SHTD plugs into."
      echo "  Without it, SHTD modules won't be loaded by Claude Code."
      ((errors++))
    fi
  fi

  # Check run-modules directories exist
  for event in PreToolUse PostToolUse Stop; do
    if [ ! -d "${HOOKS_BASE}/${event}" ]; then
      warn "Missing: ${HOOKS_BASE}/${event}/ (will create)"
    fi
  done

  # Check Python (needed for task_claims.py)
  if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    fail "Python not found. task_claims.py requires Python 3."
    ((errors++))
  fi

  # Check Node.js (needed for hooks)
  if ! command -v node >/dev/null 2>&1; then
    fail "Node.js not found. Hook modules require Node.js."
    ((errors++))
  fi

  return $errors
}

install_lib() {
  echo ""
  echo "=== Installing SHTD Flow libraries ==="
  mkdir -p "${SHTD_HOME}/lib"

  cp "${SCRIPT_DIR}/lib/audit.js" "${SHTD_HOME}/lib/audit.js"
  ok "lib/audit.js"

  cp "${SCRIPT_DIR}/lib/task_claims.py" "${SHTD_HOME}/lib/task_claims.py"
  ok "lib/task_claims.py"

  # Create data directories
  mkdir -p "${SHTD_HOME}/claims"
  ok "claims/ directory"
}

install_hooks() {
  echo ""
  echo "=== Installing SHTD Flow hook modules ==="

  for event in PreToolUse PostToolUse Stop; do
    mkdir -p "${HOOKS_BASE}/${event}"

    local src_dir="${SCRIPT_DIR}/hooks/${event}"
    if [ ! -d "$src_dir" ]; then continue; fi

    for module in "${src_dir}"/shtd_*.js; do
      [ -f "$module" ] || continue
      local name=$(basename "$module")
      cp "$module" "${HOOKS_BASE}/${event}/${name}"
      ok "${event}/${name}"
    done
  done
}

install_rules() {
  echo ""
  echo "=== Installing SHTD Flow rules ==="
  mkdir -p "${SHTD_HOME}/rules"

  for rule in "${SCRIPT_DIR}/rules"/shtd-*.md; do
    [ -f "$rule" ] || continue
    local name=$(basename "$rule")
    cp "$rule" "${SHTD_HOME}/rules/${name}"
    ok "rules/${name}"
  done
}

verify_install() {
  echo ""
  echo "=== Verifying SHTD Flow installation ==="
  local errors=0

  # Check lib files
  for f in audit.js task_claims.py; do
    if [ -f "${SHTD_HOME}/lib/${f}" ]; then
      ok "lib/${f}"
    else
      fail "lib/${f} missing"
      ((errors++))
    fi
  done

  # Check hook modules
  local expected_hooks=(
    "PreToolUse/shtd_spec-gate.js"
    "PreToolUse/shtd_test-first-gate.js"
    "PreToolUse/shtd_branch-gate.js"
    "PreToolUse/shtd_pr-per-task-gate.js"
    "PreToolUse/shtd_e2e-merge-gate.js"
    "PreToolUse/shtd_remote-tracking-gate.js"
    "PreToolUse/shtd_secret-scan-gate.js"
    "PreToolUse/shtd_task-claim.js"
    "PostToolUse/shtd_audit-logger.js"
    "Stop/shtd_task-release.js"
  )

  for hook in "${expected_hooks[@]}"; do
    if [ -f "${HOOKS_BASE}/${hook}" ]; then
      ok "${hook}"
    else
      fail "${hook} missing"
      ((errors++))
    fi
  done

  # Check rules
  local rule_count=0
  for rule in "${SHTD_HOME}/rules"/shtd-*.md; do
    [ -f "$rule" ] || continue
    ok "rules/$(basename "$rule")"
    ((rule_count++))
  done
  if [ $rule_count -eq 0 ]; then
    fail "No rule files found in ${SHTD_HOME}/rules/"
    ((errors++))
  fi

  # Test task_claims.py
  if python "${SHTD_HOME}/lib/task_claims.py" status --project-dir /tmp >/dev/null 2>&1 || \
     python3 "${SHTD_HOME}/lib/task_claims.py" status --project-dir /tmp >/dev/null 2>&1; then
    ok "task_claims.py runs"
  else
    fail "task_claims.py fails to run"
    ((errors++))
  fi

  # Test audit.js
  if node -e "require('${SHTD_HOME}/lib/audit.js')" 2>/dev/null; then
    ok "audit.js loads"
  else
    fail "audit.js fails to load"
    ((errors++))
  fi

  echo ""
  if [ $errors -eq 0 ]; then
    echo -e "${GREEN}=== SHTD Flow installed successfully ===${NC}"
    echo ""
    echo "Modules installed: $(find "${HOOKS_BASE}" -name 'shtd_*.js' 2>/dev/null | wc -l)"
    echo "Audit log: ${SHTD_HOME}/audit.jsonl"
    echo "Task claims: ${SHTD_HOME}/claims/"
    echo ""
    echo "Restart Claude Code to activate. New sessions will auto-claim tasks."
  else
    echo -e "${RED}=== ${errors} error(s) found ===${NC}"
    return 1
  fi
}

uninstall() {
  echo "=== Uninstalling SHTD Flow modules ==="
  local count=0

  # Remove hook modules (only shtd_* files)
  for event in PreToolUse PostToolUse Stop; do
    for f in "${HOOKS_BASE}/${event}"/shtd_*.js; do
      [ -f "$f" ] || continue
      # Archive instead of delete
      mkdir -p "${HOOKS_BASE}/${event}/archive"
      mv "$f" "${HOOKS_BASE}/${event}/archive/"
      ok "Archived: ${event}/$(basename "$f")"
      ((count++))
    done
  done

  echo "Archived ${count} modules. lib/ and audit log preserved in ${SHTD_HOME}/"
  echo "To fully remove: mv ${SHTD_HOME} ${SHTD_HOME}.bak"
}

# --- Main ---

case "${1:-}" in
  --check)
    check_prereqs && verify_install
    ;;
  --uninstall)
    uninstall
    ;;
  *)
    echo "=========================================="
    echo "  SHTD Flow Installer"
    echo "  Spec-Hook-Test-Driven Workflow"
    echo "=========================================="
    echo ""
    echo "This installs workflow enforcement hooks for Claude Code."
    echo "Prerequisite: hook-runner (grobomo/hook-runner)"
    echo ""

    if ! check_prereqs; then
      echo ""
      fail "Prerequisites not met. Fix the above errors first."
      exit 1
    fi
    ok "Prerequisites met"

    install_lib
    install_hooks
    install_rules
    verify_install
    ;;
esac
