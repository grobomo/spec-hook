#!/usr/bin/env bash
# Test: spec and workflow YAML exist for 005-add-workflows-to-hookrunner
set -euo pipefail
cd "$(dirname "$0")/../.."

errors=0

# Spec exists
if [ -f "specs/005-add-workflows-to-hookrunner/spec.md" ]; then
  echo "[OK] spec.md exists"
else
  echo "[FAIL] specs/005-add-workflows-to-hookrunner/spec.md missing"
  errors=$((errors + 1))
fi

# Spec has required sections
for section in "Problem" "Solution" "Architecture"; do
  if grep -qi "$section" specs/005-add-workflows-to-hookrunner/spec.md 2>/dev/null; then
    echo "[OK] spec has $section section"
  else
    echo "[FAIL] spec missing $section section"
    errors=$((errors + 1))
  fi
done

# Workflow YAML exists
if [ -f "workflows/005-add-workflows-to-hookrunner.yml" ]; then
  echo "[OK] workflow YAML exists"
else
  echo "[FAIL] workflows/005-add-workflows-to-hookrunner.yml missing"
  errors=$((errors + 1))
fi

exit $errors
