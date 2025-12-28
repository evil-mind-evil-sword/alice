#!/bin/bash
# SAFE_ID edge case tests
# Tests the issue ID sanitization logic

set -e

pass=0
fail=0

sanitize_id() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-'
}

test_sanitize() {
    local input="$1"
    local expected="$2"
    local description="$3"

    local result=$(sanitize_id "$input")

    if [[ "$result" == "$expected" ]]; then
        echo "✓ $description"
        echo "  Input: '$input' -> '$result'"
        ((pass++)) || true
    else
        echo "✗ $description"
        echo "  Input: '$input'"
        echo "  Expected: '$expected'"
        echo "  Got: '$result'"
        ((fail++)) || true
    fi
}

echo "=== SAFE_ID Sanitization Tests ==="
echo ""

echo "--- Basic Cases ---"
test_sanitize "issue-123" "issue-123" "Simple alphanumeric with dash"
test_sanitize "feature_abc" "feature_abc" "Underscore preserved"
test_sanitize "UPPERCASE" "UPPERCASE" "Uppercase preserved"

echo ""
echo "--- Edge Cases ---"
test_sanitize "" "" "Empty string -> empty"
test_sanitize "..." "" "All dots stripped"
test_sanitize "#123" "123" "Hash stripped, numbers kept"
test_sanitize "@mention" "mention" "At sign stripped"
test_sanitize "a b c" "abc" "Spaces stripped"
test_sanitize "a/b/c" "abc" "Slashes stripped"
test_sanitize "../../../etc/passwd" "etcpasswd" "Path traversal neutralized"

echo ""
echo "--- Injection Attempts ---"
test_sanitize "-n" "-n" "Echo -n flag (preserved, but harmless as path)"
test_sanitize "-e" "-e" "Echo -e flag (preserved, but harmless as path)"
test_sanitize "\$(whoami)" "whoami" "Command substitution stripped"
test_sanitize "\`id\`" "id" "Backticks stripped"
test_sanitize "a;rm -rf /" "arm-rf" "Semicolon injection stripped"
test_sanitize "a|cat /etc/passwd" "acatetcpasswd" "Pipe injection stripped"

echo ""
echo "--- Length Cases ---"
LONG_ID=$(printf 'a%.0s' {1..256})
LONG_RESULT=$(sanitize_id "$LONG_ID")
if [[ ${#LONG_RESULT} -eq 256 ]]; then
    echo "✓ 256-char ID preserved (length: ${#LONG_RESULT})"
    ((pass++)) || true
else
    echo "✗ 256-char ID (expected 256, got ${#LONG_RESULT})"
    ((fail++)) || true
fi

echo ""
echo "--- Case Sensitivity (filesystem collision risk) ---"
ID_UPPER=$(sanitize_id "TestCase")
ID_LOWER=$(sanitize_id "testcase")
if [[ "$ID_UPPER" != "$ID_LOWER" ]]; then
    echo "✓ Case preserved: '$ID_UPPER' vs '$ID_LOWER'"
    echo "  WARNING: These will collide on case-insensitive filesystems (macOS default)"
    ((pass++)) || true
else
    echo "✗ Case folded unexpectedly"
    ((fail++)) || true
fi

echo ""
echo "--- Collision Pairs ---"
echo "These inputs produce identical SAFE_IDs:"
echo "  'a*b' and 'ab' -> '$(sanitize_id "a*b")' and '$(sanitize_id "ab")'"
echo "  'a.b' and 'ab' -> '$(sanitize_id "a.b")' and '$(sanitize_id "ab")'"
echo "  'a/b' and 'ab' -> '$(sanitize_id "a/b")' and '$(sanitize_id "ab")'"
echo "  (This is expected behavior - special chars are stripped)"

echo ""
echo "=== Summary ==="
echo "Passed: $pass"
echo "Failed: $fail"

if [[ $fail -gt 0 ]]; then
    exit 1
fi
