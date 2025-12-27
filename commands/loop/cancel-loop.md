---
description: Cancel the active loop
---

# Cancel Loop

Stop the current iteration loop.

## Steps

1. Check for active issue:
   ```bash
   cat /tmp/trivial-loop-issue 2>/dev/null
   ```

2. If issue in progress, pause it:
   ```bash
   ISSUE_ID=$(cat /tmp/trivial-loop-issue 2>/dev/null)
   [[ -n "$ISSUE_ID" ]] && tissue status "$ISSUE_ID" paused
   ```

3. Clean up:
   ```bash
   rm -f /tmp/trivial-loop-*
   ```

4. Summarize what was accomplished
