---
description: Iterate on a task until complete, or work through the issue tracker
---

# /loop

Iterate on a task or work through your issue backlog.

## Usage

```
/loop [task description]
```

## Modes

### Task Mode (with arguments)

```sh
/loop Add input validation to API endpoints
```

Iterates on the task until complete. No issue tracker needed.

- **Max iterations**: 10
- **Worktree**: No (works in current directory)
- **Auto-land**: No

### Issue Mode (no arguments)

```sh
/loop
```

Pulls issues from `tissue ready`, works them one by one.

- **Max iterations**: 10 per issue
- **Worktree**: Yes (isolates each issue in `.worktrees/idle/<issue-id>/`)
- **Auto-land**: Yes (merges to main on completion)

## Completion Signals

Signal completion status in your response:

| Signal | Meaning |
|--------|---------|
| `<loop-done>COMPLETE</loop-done>` | Task finished successfully |
| `<loop-done>STUCK</loop-done>` | Cannot make progress |
| `<loop-done>MAX_ITERATIONS</loop-done>` | Hit iteration limit |

## Alice Review

When you signal `COMPLETE` or `STUCK`, the Stop hook:
1. Blocks exit
2. Requests alice review
3. Alice analyzes your work
4. If approved → exit. If not → continue.

This ensures quality before completion.

## Issue Mode Workflow

1. `/loop` picks first ready issue from tissue
2. Creates worktree at `.worktrees/idle/<issue-id>/`
3. You work on the issue
4. Signal `<loop-done>COMPLETE</loop-done>`
5. alice reviews
6. Auto-lands: merges to main, deletes worktree, closes issue
7. Picks next issue, repeats

## Escape Hatches

```sh
/cancel                  # Graceful cancellation
touch .idle-disabled     # Bypass hooks
rm -rf .jwz/             # Reset all state
```
