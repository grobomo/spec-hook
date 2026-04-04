#!/usr/bin/env bash
# Test: YAML parser edge cases — empty steps, missing fields, malformed input
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

run_parse() {
  # Pass YAML string to parseYaml via argv (avoids path escaping issues)
  node -e "
    const path = require('path');
    const wf = require(path.join(process.cwd(), 'lib', 'workflow.js'));
    const yaml = process.argv[1];
    try {
      const result = wf.parseYaml(yaml);
      console.log(JSON.stringify(result));
    } catch(e) {
      console.log('ERROR:' + e.message);
    }
  " -- "$1"
}

run_load() {
  # Write YAML to temp file, load as workflow
  local tmpfile=$(mktemp /tmp/wf-XXXXXX.yml)
  echo "$1" > "$tmpfile"
  node -e "
    const path = require('path');
    const wf = require(path.join(process.cwd(), 'lib', 'workflow.js'));
    try {
      const result = wf.loadWorkflow(path.resolve(process.argv[1]));
      console.log(JSON.stringify(result));
    } catch(e) {
      console.log('ERROR:' + e.message);
    }
  " -- "$tmpfile"
  rm -f "$tmpfile"
}

echo "=== 1. Empty input ==="
result=$(run_parse "")
[[ "$result" == "{}" ]] && pass "Empty string returns empty object" || fail "Empty string: got $result"

echo ""
echo "=== 2. Comments only ==="
result=$(run_parse "# just a comment
# another comment")
[[ "$result" == "{}" ]] && pass "Comments-only returns empty object" || fail "Comments-only: got $result"

echo ""
echo "=== 3. Name only, no steps ==="
result=$(run_load "name: my-workflow")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.name === 'my-workflow' && Array.isArray(d.steps) && d.steps.length === 0) {
    process.exit(0);
  } else { process.exit(1); }
" && pass "Name-only workflow has empty steps array" || fail "Name-only: got $result"

echo ""
echo "=== 4. Steps with missing fields ==="
result=$(run_load "name: partial
steps:
  - id: step1
  - id: step2
    name: Step Two")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  const s1 = d.steps[0], s2 = d.steps[1];
  if (s1.id === 'step1' && s1.name === 'step1' && s1.gate && s1.completion &&
      s2.id === 'step2' && s2.name === 'Step Two') {
    process.exit(0);
  } else { process.exit(1); }
" && pass "Missing fields get defaults (name=id, empty gate/completion)" || fail "Missing fields: got $result"

echo ""
echo "=== 5. Empty steps array ==="
result=$(run_load "name: empty-steps
steps:")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.steps.length === 0) process.exit(0); else process.exit(1);
" && pass "Empty steps: produces empty array" || fail "Empty steps: got $result"

echo ""
echo "=== 6. Inline array values ==="
result=$(run_parse 'name: test
steps:
  - id: s1
    gate:
      require_files: ["a.txt", "b.txt"]')
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  const files = d.steps[0].gate.require_files;
  if (Array.isArray(files) && files.length === 2 && files[0] === 'a.txt' && files[1] === 'b.txt') {
    process.exit(0);
  } else { process.exit(1); }
" && pass "Inline arrays parsed correctly" || fail "Inline arrays: got $result"

echo ""
echo "=== 7. Empty inline array ==="
result=$(run_parse 'name: test
steps:
  - id: s1
    gate:
      require_files: []')
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  const files = d.steps[0].gate.require_files;
  if (Array.isArray(files) && files.length === 0) process.exit(0); else process.exit(1);
" && pass "Empty inline array parsed correctly" || fail "Empty inline array: got $result"

echo ""
echo "=== 8. Boolean and null scalars ==="
result=$(run_parse "flag_true: true
flag_false: false
empty_val: ~
null_val: null")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.flag_true === true && d.flag_false === false && d.empty_val === null && d.null_val === null) {
    process.exit(0);
  } else { process.exit(1); }
" && pass "Booleans and null parsed correctly" || fail "Scalars: got $result"

echo ""
echo "=== 9. Quoted strings with colons ==="
result=$(run_parse 'title: "Step 1: Setup"')
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.title === 'Step 1: Setup') process.exit(0); else process.exit(1);
" && pass "Quoted string with colon preserved" || fail "Quoted colon: got $result"

echo ""
echo "=== 10. Integer values ==="
result=$(run_parse "version: 2
timeout: 300")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.version === 2 && d.timeout === 300) process.exit(0); else process.exit(1);
" && pass "Integers parsed as numbers" || fail "Integers: got $result"

echo ""
echo "=== 11. Duplicate keys — last wins ==="
result=$(run_parse "name: first
name: second")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.name === 'second') process.exit(0); else process.exit(1);
" && pass "Duplicate keys: last value wins" || fail "Duplicate keys: got $result"

echo ""
echo "=== 12. Real workflow file ==="
result=$(run_load "$(cat "$PROJECT_DIR/workflows/test-claude-install.yml")")
echo "$result" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf-8'));
  if (d.name && d.steps.length >= 3 && d.steps.every(s => s.id && s.name)) {
    process.exit(0);
  } else { process.exit(1); }
" && pass "Real workflow parses with all steps" || fail "Real workflow: got $result"

echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL tests"
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASSED"
else
  echo "$FAIL FAILED"
  exit 1
fi
