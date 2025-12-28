#!/bin/bash
# Stop hook unit tests
# Tests edge cases in transcript parsing and state handling

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

pass=0
fail=0

test_case() {
    local name="$1"
    local expected="$2"
    shift 2

    if "$@" >/dev/null 2>&1; then
        result="pass"
    else
        result="fail"
    fi

    if [[ "$result" == "$expected" ]]; then
        echo "✓ $name"
        ((pass++)) || true
    else
        echo "✗ $name (expected $expected, got $result)"
        ((fail++)) || true
    fi
}

echo "=== Stop Hook Tests ==="
echo ""

# Test 1: No state file, no jwz - should exit cleanly (exit 0)
echo "--- No Active Loop ---"
(
    cd "$TEMP_DIR"
    echo '{}' | bash "$HOOK"
) && test_case "No state exits cleanly" "pass" true || test_case "No state exits cleanly" "pass" false

# Test 2: Completion signal in code block (false positive risk)
echo ""
echo "--- False Positive Tests ---"
mkdir -p "$TEMP_DIR/codeblock"
cat > "$TEMP_DIR/codeblock/transcript.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Here's how to signal completion:\n```\n<loop-done>COMPLETE</loop-done>\n```\nBut we're not done yet."}]}}
EOF

# This tests that we DON'T have protection against code block false positives
# (known limitation - documenting behavior)
echo "Note: Code block false positives are a known limitation"

# Test 3: Corrupt JSON in transcript
echo ""
echo "--- Corrupt Data Handling ---"
mkdir -p "$TEMP_DIR/corrupt"
cat > "$TEMP_DIR/corrupt/transcript.jsonl" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Working on it...
EOF
# Intentionally malformed JSON

(
    cd "$TEMP_DIR/corrupt"
    mkdir -p .jwz
    echo '{"schema":1,"event":"STATE","run_id":"test","stack":[{"id":"test","mode":"loop","iter":1,"max":10}]}' > .jwz/loop_current
    echo '{"transcript_path":"'"$TEMP_DIR/corrupt/transcript.jsonl"'","cwd":"'"$TEMP_DIR/corrupt"'"}' | bash "$HOOK" 2>/dev/null
    exit_code=$?
    # Should either continue (exit 2) or handle gracefully (exit 0)
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 2 ]]
) && test_case "Corrupt transcript handled gracefully" "pass" true || test_case "Corrupt transcript handled gracefully" "fail" true

# Test 4: Stale state (>2 hours old)
echo ""
echo "--- Staleness Detection ---"
mkdir -p "$TEMP_DIR/stale/.jwz"
OLD_TIME=$(date -u -v-3H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "3 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
cat > "$TEMP_DIR/stale/.jwz/loop_current" << EOF
{"schema":1,"event":"STATE","run_id":"stale-test","updated_at":"$OLD_TIME","stack":[{"id":"test","mode":"loop","iter":1,"max":10}]}
EOF

# Note: The hook reads from jwz topic, not file directly. This test is illustrative.
echo "Note: Staleness test requires jwz integration"

# Test 5: Max iterations reached
echo ""
echo "--- Iteration Limits ---"
echo "Note: Max iteration test requires jwz integration"

# Summary
echo ""
echo "=== Summary ==="
echo "Passed: $pass"
echo "Failed: $fail"
echo ""
echo "Note: Full integration tests require a running Claude session with jwz."
echo "These unit tests verify isolated behavior only."

if [[ $fail -gt 0 ]]; then
    exit 1
fi
