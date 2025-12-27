---
description: Iterate on a task until complete
---

# Loop Command

Generic iteration loop for any task (no issue tracker).

## Usage

```
/loop <task description>
```

## Limits

- **Max iterations**: 10
- **Stuck threshold**: 3 consecutive failures with no progress

## Workflow

1. Work on the task incrementally
2. Run `/test` after significant changes
3. On success: output `<loop-done>COMPLETE</loop-done>`
4. On failure: analyze, fix, retry (up to limit)

## Session State

Use a unique session ID to avoid conflicts:
```bash
# Generate session ID if not set
SID="${TRIVIAL_SESSION_ID:-$(date +%s)-$$}"
export TRIVIAL_SESSION_ID="$SID"
STATE_DIR="/tmp/trivial-$SID"
mkdir -p "$STATE_DIR"
```

## Iteration Tracking

Track your iteration count:
```bash
ITER=$(($(cat "$STATE_DIR/iter" 2>/dev/null || echo 0) + 1))
echo "$ITER" > "$STATE_DIR/iter"
```

Before each retry:
- `git status` - modified files
- `git log --oneline -5` - what you've tried

## Completion

**Success**:
```
<loop-done>COMPLETE</loop-done>
```

**Max iterations reached**:
```
<loop-done>MAX_ITERATIONS</loop-done>
```
Report what was accomplished and what remains.

**Stuck** (no progress after 3 attempts):
```
<loop-done>STUCK</loop-done>
```
Describe the blocker and ask for user guidance.

## Cleanup

On completion (any outcome):
```bash
rm -rf "$STATE_DIR"
unset TRIVIAL_SESSION_ID
```
