#!/bin/bash
# Unit tests - run with stubbed dependencies (CI-safe)
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

run_test() {
  local test_file="$1"
  local name=$(basename "$test_file" .lua | sed 's/test_//' | tr '_' ' ')

  result=$(nvim --headless -u tests/minimal_init.lua -c "luafile $test_file" -c "qa!" 2>&1)

  if echo "$result" | grep -q "^PASS"; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name"
    echo "  Output: $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Unit Tests (stubbed dependencies) ==="

for test_file in tests/unit/test_*.lua; do
  run_test "$test_file"
done

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
