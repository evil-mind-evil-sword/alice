---
description: Continuously work through the issue tracker
---

# Grind Command

Run `/issue` in a loop over all matching issues.

## Usage

```
/grind [filter]
```

Filter examples: `repl`, `epic:slop2-abc`, `priority:1`

## Limits

- **Max issues per session**: 10
- **Per-issue limit**: Inherited from `/issue` (10 iterations)

## Session State

```bash
# Generate unique session ID
SID="$(date +%s)-$$"
export TRIVIAL_SESSION_ID="$SID"
STATE_DIR="/tmp/trivial-$SID"
mkdir -p "$STATE_DIR"
```

## Setup

```bash
echo "grind" > "$STATE_DIR/mode"
echo "$ARGUMENTS" > "$STATE_DIR/context"
echo "0" > "$STATE_DIR/count"
```

## Workflow

Repeat until limit or no issues:

1. **Check limits**:
   ```bash
   COUNT=$(cat "$STATE_DIR/count")
   if [ "$COUNT" -ge 10 ]; then
     echo "<grind-done>MAX_ISSUES</grind-done>"
     exit
   fi
   ```

2. **Find next issue**:
   - `tissue ready --json`
   - Filter by context (tag, epic, priority) if provided
   - Pick highest priority match (P1 > P2 > P3)
   - If none remain: `<grind-done>NO_MORE_ISSUES</grind-done>`

3. **Work it**: Run `/issue <issue-id>`

4. **Track**:
   ```bash
   echo "$((COUNT + 1))" > "$STATE_DIR/count"
   ```

5. **On completion**: Output `<issue-complete>DONE</issue-complete>`

6. **Continue**: Go to step 1

## Pause Conditions

If `/issue` returns STUCK or MAX_ITERATIONS:
- Issue is already paused by `/issue`
- Continue to next issue

## Completion

**All done**:
```
<grind-done>NO_MORE_ISSUES</grind-done>
```

**Session limit**:
```
<grind-done>MAX_ISSUES</grind-done>
```
Report: X issues completed, Y remaining.

**User cancelled**: `/cancel-loop`

## Cleanup

```bash
rm -rf "$STATE_DIR"
unset TRIVIAL_SESSION_ID
```
