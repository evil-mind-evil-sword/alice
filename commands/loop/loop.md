---
description: Iterate on a task until complete
---

# Loop Command

Generic iteration loop for any task (no issue tracker).

## Usage

```
/loop <task description>
```

## Workflow

1. Work on the task incrementally
2. Run `/test` after significant changes
3. On success: output `<loop-done>COMPLETE</loop-done>`
4. On failure: analyze, fix, retry

## Iteration Context

Before each retry:
- `git status` - modified files
- `git log --oneline -5` - what you've tried

## Completion

When the task is complete:

```
<loop-done>COMPLETE</loop-done>
```

Keep iterating until success. Do not give up.
