---
description: Work an issue with iteration (retries on failure)
---

# Issue Command

Like `/work`, but with iteration - keep trying until the issue is resolved.

## Usage

```
/issue <issue-id>
```

## Setup

```bash
echo "$ARGUMENTS" > /tmp/trivial-loop-issue
```

## Workflow

Run `/work $ARGUMENTS` with these additions:

1. **On failure**: Don't give up. Analyze what went wrong and retry.
2. **On stuck**: Check your iteration context (below) before trying again.
3. **On success**: Output `<loop-done>COMPLETE</loop-done>`

## Iteration Context

Before each retry, review your previous work:
- `git status` - modified files
- `git log --oneline -10` - recent commits
- `tissue show $ARGUMENTS` - re-read the issue

## Completion

When `/work` succeeds (review passes, issue closed):

```
<loop-done>COMPLETE</loop-done>
```

Keep iterating until success. Do not give up.
