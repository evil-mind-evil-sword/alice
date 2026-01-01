#!/bin/bash
# idle STOP hook
# Gates exit on alice review - alice makes the judgment call
#
# Output: JSON with decision (block/approve) and reason
# Exit 0 for both - decision field controls behavior

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Check if stop hook already triggered (prevent infinite loops)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    jq -n '{decision: "approve", reason: "Stop hook already active"}'
    exit 0
fi

# Extract session info
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

cd "$CWD"

ALICE_TOPIC="alice:status:$SESSION_ID"
USER_CONTEXT_TOPIC="user:context:$SESSION_ID"

# --- Check: Has alice reviewed this session? ---

ALICE_DECISION=""
ALICE_MSG_ID=""
ALICE_SUMMARY=""
ALICE_MESSAGE=""

if command -v jwz &>/dev/null; then
    LATEST_RAW=$(jwz read "$ALICE_TOPIC" --json 2>/dev/null | jq '.[-1] // empty' || echo "")
    if [[ -n "$LATEST_RAW" ]]; then
        ALICE_MSG_ID=$(echo "$LATEST_RAW" | jq -r '.id // ""')
        LATEST_BODY=$(echo "$LATEST_RAW" | jq -r '.body // ""')
        if [[ -n "$LATEST_BODY" ]]; then
            ALICE_DECISION=$(echo "$LATEST_BODY" | jq -r '.decision // ""' 2>/dev/null || echo "")
            ALICE_SUMMARY=$(echo "$LATEST_BODY" | jq -r '.summary // ""' 2>/dev/null || echo "")
            ALICE_MESSAGE=$(echo "$LATEST_BODY" | jq -r '.message_to_agent // ""' 2>/dev/null || echo "")
        fi
    fi
fi

# --- Decision: COMPLETE/APPROVED → allow exit ---

if [[ "$ALICE_DECISION" == "COMPLETE" || "$ALICE_DECISION" == "APPROVED" ]]; then
    REASON="alice approved"
    [[ -n "$ALICE_MSG_ID" ]] && REASON="$REASON (msg: $ALICE_MSG_ID)"
    [[ -n "$ALICE_SUMMARY" ]] && REASON="$REASON - $ALICE_SUMMARY"
    jq -n --arg reason "$REASON" '{decision: "approve", reason: $reason}'
    exit 0
fi

# --- Decision: ISSUES → block, pass alice's message ---

if [[ "$ALICE_DECISION" == "ISSUES" ]]; then
    REASON="alice found issues that need to be addressed before exiting."
    [[ -n "$ALICE_MSG_ID" ]] && REASON="$REASON (review: $ALICE_MSG_ID)"
    [[ -n "$ALICE_SUMMARY" ]] && REASON="$REASON

$ALICE_SUMMARY"
    [[ -n "$ALICE_MESSAGE" ]] && REASON="$REASON

alice says: $ALICE_MESSAGE"
    jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
    exit 0
fi

# --- No review yet → request alice review ---

REASON="No alice review for this session. Spawn the idle:alice agent to get review approval before exiting.

Use: Task tool with subagent_type='idle:alice' and prompt including SESSION_ID=$SESSION_ID

Alice will read your conversation context and decide if the work is complete or needs fixes."

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
