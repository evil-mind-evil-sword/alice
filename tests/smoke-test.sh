#!/bin/bash
# Smoke test for trivial worktree workflow
# Run this manually in a test repository with tissue set up

set -e

echo "=== Trivial Worktree Smoke Test ==="
echo ""
echo "Prerequisites:"
echo "  - tissue installed and configured"
echo "  - jwz (zawinski) installed"
echo "  - In a git repository"
echo ""

# Check prerequisites
check_prereq() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "✗ Missing: $1"
        return 1
    else
        echo "✓ Found: $1"
        return 0
    fi
}

echo "--- Checking Prerequisites ---"
check_prereq git || exit 1
check_prereq tissue || exit 1
check_prereq jwz || exit 1
check_prereq jq || exit 1

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "✗ Not in a git repository"
    exit 1
fi
echo "✓ In git repository: $(git rev-parse --show-toplevel)"

echo ""
echo "--- Test Steps (run manually in Claude) ---"
echo ""
echo "1. Create a test issue:"
echo "   tissue new 'smoke-test-issue' -m 'Test issue for worktree smoke test'"
echo ""
echo "2. Start working the issue:"
echo "   /issue smoke-test-issue"
echo ""
echo "3. Verify worktree was created:"
echo "   /worktree status"
echo "   # Should show: smoke-test-issue: clean (0 commits)"
echo ""
echo "4. Make a change in the worktree:"
echo "   echo 'test' > test-file.txt"
echo "   git add test-file.txt"
echo "   git commit -m 'Test commit'"
echo ""
echo "5. Signal completion:"
echo "   <loop-done>COMPLETE</loop-done>"
echo ""
echo "6. Verify worktree status:"
echo "   /worktree status"
echo "   # Should show: smoke-test-issue: clean (1 commits)"
echo ""
echo "7. Land the changes:"
echo "   /land smoke-test-issue"
echo ""
echo "8. Verify cleanup:"
echo "   git worktree list"
echo "   # Should not show the test worktree"
echo "   git log --oneline -3"
echo "   # Should show the 'Test commit'"
echo ""
echo "9. Cleanup test issue:"
echo "   tissue close smoke-test-issue"
echo "   git reset --hard HEAD~1  # Remove test commit"
echo ""
echo "--- Chaos Tests (optional) ---"
echo ""
echo "A. Kill mid-loop:"
echo "   /issue some-issue"
echo "   # Ctrl+C or kill the process"
echo "   /worktree prune"
echo "   # Should recover gracefully"
echo ""
echo "B. Case collision (macOS):"
echo "   tissue new 'TestCase' -m 'Uppercase'"
echo "   tissue new 'testcase' -m 'Lowercase'"
echo "   /issue TestCase"
echo "   /issue testcase"
echo "   # Second should error with collision warning"
echo ""
echo "C. Corrupt state:"
echo "   echo 'garbage' > .jwz/topics/loop_current/001.msg"
echo "   # Next loop iteration should handle gracefully"
