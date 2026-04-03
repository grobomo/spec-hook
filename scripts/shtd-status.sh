#!/usr/bin/env bash
# SHTD Status — Show workflow status for a project
# Usage: bash shtd-status.sh [project-dir]

set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

SHTD_HOME="${HOME}/.claude/shtd-flow"
AUDIT_FILE="${SHTD_HOME}/audit.jsonl"
CLAIMS_PY="${SHTD_HOME}/lib/task_claims.py"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}=== SHTD Status: ${PROJECT_NAME} ===${NC}"
echo ""

# Task claims
if [ -f "$CLAIMS_PY" ]; then
  echo -e "${CYAN}Task Claims:${NC}"
  python "$CLAIMS_PY" status --project-dir "$PROJECT_DIR" 2>/dev/null || echo "  (no claims data)"
  echo ""
fi

# Recent audit events
if [ -f "$AUDIT_FILE" ]; then
  echo -e "${CYAN}Recent Events (last 10):${NC}"
  grep "\"project\":\"${PROJECT_NAME}\"" "$AUDIT_FILE" 2>/dev/null | tail -10 | while IFS= read -r line; do
    ts=$(echo "$line" | python -c "import sys,json; print(json.load(sys.stdin).get('ts','?')[:19])" 2>/dev/null || echo "?")
    event=$(echo "$line" | python -c "import sys,json; print(json.load(sys.stdin).get('event','?'))" 2>/dev/null || echo "?")
    task=$(echo "$line" | python -c "import sys,json; print(json.load(sys.stdin).get('task',''))" 2>/dev/null || echo "")
    printf "  %-20s %-20s %s\n" "$ts" "$event" "$task"
  done
  echo ""
fi

# Specs check
echo -e "${CYAN}Workflow Checks:${NC}"
if [ -d "${PROJECT_DIR}/specs" ]; then
  spec_count=$(find "${PROJECT_DIR}/specs" -name "spec.md" 2>/dev/null | wc -l)
  echo -e "  Specs:           ${GREEN}${spec_count} found${NC}"
else
  echo -e "  Specs:           ${RED}No specs/ directory${NC}"
fi

# Branch
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    echo -e "  Branch:          ${YELLOW}${branch} (create a feature branch)${NC}"
  else
    echo -e "  Branch:          ${GREEN}${branch}${NC}"
  fi

  if git -C "$PROJECT_DIR" rev-parse --abbrev-ref "${branch}@{upstream}" >/dev/null 2>&1; then
    echo -e "  Remote tracking: ${GREEN}yes${NC}"
  else
    echo -e "  Remote tracking: ${RED}no${NC}"
  fi
fi

# Secret scan
if [ -f "${PROJECT_DIR}/.github/workflows/secret-scan.yml" ]; then
  echo -e "  Secret scan:     ${GREEN}present${NC}"
else
  echo -e "  Secret scan:     ${RED}missing${NC}"
fi

# Test results
if [ -d "${PROJECT_DIR}/.test-results" ]; then
  passed=$(find "${PROJECT_DIR}/.test-results" -name "*.passed" 2>/dev/null | wc -l)
  echo -e "  Test results:    ${GREEN}${passed} passed${NC}"
else
  echo -e "  Test results:    ${YELLOW}no .test-results/${NC}"
fi

echo ""
