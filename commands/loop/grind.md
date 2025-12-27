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

## Setup

```bash
echo "grind" > /tmp/trivial-loop-mode
echo "$ARGUMENTS" > /tmp/trivial-loop-context
```

## Workflow

Repeat until no issues remain:

1. **Find next issue**:
   - `tissue ready --json`
   - Filter by context (tag, epic, priority) if provided
   - Pick highest priority match (P1 > P2 > P3)
   - If none remain: output `<grind-done>NO_MORE_ISSUES</grind-done>` and stop

2. **Work it**: Run `/issue <issue-id>`

3. **On completion**: Output `<issue-complete>DONE</issue-complete>`

4. **Continue**: Go to step 1

## Pause Conditions

If stuck too long on one issue:
```bash
tissue status <issue-id> paused
tissue comment <issue-id> -m "[grind] Needs human input"
```
Then continue to next issue.

## To Stop

User runs `/cancel-loop`, or no matching issues remain.

Keep grinding.
