---
description: Run code review via reviewer agent
---

# Review Command

Run code review on current changes using the reviewer agent.

## Usage

```
/review [issue-id]
```

## Pre-check

First, verify there are changes to review:
```bash
git diff --stat
git diff --cached --stat
```

If **no changes** (both empty):
- Report "No changes to review"
- Stop

## Steps

Invoke the reviewer agent:

```
Task(subagent_type="idle:reviewer", prompt="Review the current changes. $ARGUMENTS")
```

The reviewer agent will:
1. Run `git diff` to see changes
2. Look for project style guides in docs/ or CONTRIBUTING.md
3. Collaborate with Codex for a second opinion
4. Return verdict: LGTM or CHANGES_REQUESTED

## Post-Review

After the reviewer agent returns, persist review state for the stop hook:

```bash
# Get current HEAD SHA
CURRENT_SHA=$(git rev-parse HEAD)

# Determine verdict from reviewer output
# The reviewer returns "LGTM" or "CHANGES_REQUESTED"
REVIEW_VERDICT="$REVIEWER_VERDICT"  # Set by parsing reviewer output

# Update loop state with review markers (if in a loop)
if command -v jwz >/dev/null 2>&1 && [ -d .jwz ]; then
    STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
    if [ -n "$STATE" ] && echo "$STATE" | jq -e '.stack | length > 0' >/dev/null 2>&1; then
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        RUN_ID=$(echo "$STATE" | jq -r '.run_id')
        CURRENT_ITER=$(echo "$STATE" | jq -r '.stack[-1].review_iter // 0')
        NEW_ITER=$((CURRENT_ITER + 1))

        # Update top frame with review tracking
        NEW_STACK=$(echo "$STATE" | jq \
            --arg sha "$CURRENT_SHA" \
            --arg status "$REVIEW_VERDICT" \
            --argjson iter "$NEW_ITER" \
            '.stack[-1].last_reviewed_sha = $sha | .stack[-1].last_review_status = $status | .stack[-1].review_iter = $iter')

        jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$(echo "$NEW_STACK" | jq -c '.stack')}"
    fi
fi
```

Review state fields:
- `last_reviewed_sha`: HEAD at time of review
- `last_review_status`: "LGTM" or "CHANGES_REQUESTED"
- `review_iter`: Number of review iterations (for max 3 limit)

The stop hook uses these to enforce:
1. Code must be reviewed before completing
2. CHANGES_REQUESTED must be addressed with another review
3. After 3 review iterations, must create follow-up issues
