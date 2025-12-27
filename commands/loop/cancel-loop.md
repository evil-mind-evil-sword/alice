---
description: Cancel the active loop
---

# Cancel Loop

Stop the current iteration loop.

## Steps

1. Find session state:
   ```bash
   STATE_DIR="/tmp/trivial-$TRIVIAL_SESSION_ID"
   ```

2. Check for active issue:
   ```bash
   cat "$STATE_DIR/issue" 2>/dev/null
   ```

3. If issue in progress, pause it:
   ```bash
   ISSUE_ID=$(cat "$STATE_DIR/issue" 2>/dev/null)
   [[ -n "$ISSUE_ID" ]] && tissue status "$ISSUE_ID" paused
   ```

4. Clean up:
   ```bash
   rm -rf "$STATE_DIR"
   unset TRIVIAL_SESSION_ID
   ```

5. Summarize what was accomplished
