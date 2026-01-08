#!/bin/bash
# idle STOP hook
# Gates exit on alice review - if review is enabled, alice must approve.
#
# Output: JSON with decision (block/approve) and reason
# Exit 0 for both - decision field controls behavior
#
# FAIL-OPEN DESIGN:
# Infrastructure errors (jwz unavailable, state corruption, parse errors) fail OPEN
# with warnings posted to idle:warnings:{session} topic. Users can check warnings
# via `idle warnings` CLI command. This prioritizes availability over strict gating.
#
# Only alice review decisions block - NOT infrastructure issues.
#
# CIRCUIT BREAKER:
# To prevent infinite loops when an agent fails to re-invoke alice after being blocked,
# we track how many times we've blocked on the same review ID. After 3 blocks on the
# same stale review, we fail open with a warning. This prevents stack overflows and
# runaway loops while still enforcing review for cooperative agents.

# Critical: Always output valid JSON, even on error. Fail open on error.
trap 'jq -n "{decision: \"approve\", reason: \"idle: hook error - failing open\"}"; exit 0' ERR

set -uo pipefail

# Read hook input from stdin
INPUT=$(cat || echo '{}')

# Extract session info
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')

cd "$CWD"

# Ensure global store is used by default (hooks run in separate processes)
IDLE_DIR="${HOME}/.claude/idle"
export JWZ_STORE="${JWZ_STORE:-$IDLE_DIR/.jwz}"

ALICE_TOPIC="alice:status:$SESSION_ID"
REVIEW_STATE_TOPIC="review:state:$SESSION_ID"
WARNINGS_TOPIC="idle:warnings:$SESSION_ID"

# --- Helper: emit warning and fail open ---
# Logs to stderr, posts to jwz warnings topic, returns approve with additionalContext
emit_warning_and_approve() {
    local msg="$1"
    local reason="${2:-$msg}"

    # Layer 1: stderr (shown in verbose mode)
    printf "idle: WARNING: %s\n" "$msg" >&2

    # Layer 2: jwz persistence (best effort - may fail if jwz is the problem)
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jwz topic new "$WARNINGS_TOPIC" >/dev/null 2>&1 || true
    jwz post "$WARNINGS_TOPIC" -m "$(jq -n --arg w "$msg" --arg ts "$ts" '{warning: $w, timestamp: $ts}')" >/dev/null 2>&1 || true

    # Layer 3: approve with additionalContext for inline display
    jq -n --arg reason "$reason" --arg msg "⚠️ idle: $msg" '{
        decision: "approve",
        reason: $reason,
        hookSpecificOutput: {
            hookEventName: "Stop",
            additionalContext: $msg
        }
    }'
    exit 0
}

# --- Check review state (opt-in via #idle) ---

if ! command -v jwz &>/dev/null; then
    # Fail open - review system can't function without jwz
    printf "idle: WARNING: jwz unavailable - review system bypassed\n" >&2
    jq -n '{decision: "approve", reason: "jwz unavailable - review system bypassed"}'
    exit 0
fi

# Try to read review state using temp file to preserve JSON integrity
JWZ_TMPFILE=$(mktemp)
trap "rm -f $JWZ_TMPFILE" EXIT

set +e
jwz read "$REVIEW_STATE_TOPIC" --json > "$JWZ_TMPFILE" 2>&1
JWZ_EXIT=$?
set -e

# Determine review state
if [[ $JWZ_EXIT -ne 0 ]]; then
    # jwz command failed
    if command grep -q "Topic not found" "$JWZ_TMPFILE" || command grep -q "No store found" "$JWZ_TMPFILE"; then
        # Topic or store doesn't exist - #idle was never used, approve
        jq -n '{decision: "approve", reason: "Review not enabled"}'
        exit 0
    else
        # Unknown jwz error - fail OPEN with warning (user can check `idle warnings`)
        ERR_MSG=$(cat "$JWZ_TMPFILE")
        emit_warning_and_approve "jwz error while checking review state: $ERR_MSG" "jwz error - failing open with warning"
    fi
fi

# jwz succeeded - parse the response

# First check if topic is empty (exists but no messages)
# This happens when #idle was used but jwz post failed silently
TOPIC_LENGTH=$(jq 'length' "$JWZ_TMPFILE" 2>/dev/null || echo "0")
if [[ "$TOPIC_LENGTH" == "0" ]]; then
    # Topic exists but is empty - #idle was attempted but failed
    # Fail OPEN with warning (user can check `idle warnings`)
    emit_warning_and_approve "review:state topic exists but is empty - #idle may have failed" "Review state corrupted - failing open with warning"
fi

REVIEW_ENABLED_RAW=$(jq -r '.[0].body | fromjson | .enabled' "$JWZ_TMPFILE" 2>/dev/null || echo "")
if [[ -z "$REVIEW_ENABLED_RAW" || "$REVIEW_ENABLED_RAW" == "null" ]]; then
    # Can't parse enabled field - fail OPEN with warning (user can check `idle warnings`)
    emit_warning_and_approve "Failed to parse review state - state may be corrupted" "Parse error - failing open with warning"
fi

if [[ "$REVIEW_ENABLED_RAW" != "true" ]]; then
    # enabled is explicitly false - approve
    jq -n '{decision: "approve", reason: "Review not enabled"}'
    exit 0
fi

# Review is enabled - check alice's decision

ALICE_DECISION=""
ALICE_MSG_ID=""
ALICE_SUMMARY=""
ALICE_MESSAGE=""

LATEST_RAW=$(jwz read "$ALICE_TOPIC" --json 2>/dev/null | jq '.[0] // empty' || echo "")
if [[ -n "$LATEST_RAW" ]]; then
    ALICE_MSG_ID=$(echo "$LATEST_RAW" | jq -r '.id // ""')
    LATEST_BODY=$(echo "$LATEST_RAW" | jq -r '.body // ""')
    if [[ -n "$LATEST_BODY" ]]; then
        ALICE_DECISION=$(echo "$LATEST_BODY" | jq -r '.decision // ""' 2>/dev/null || echo "")
        ALICE_SUMMARY=$(echo "$LATEST_BODY" | jq -r '.summary // ""' 2>/dev/null || echo "")
        ALICE_MESSAGE=$(echo "$LATEST_BODY" | jq -r '.message_to_agent // ""' 2>/dev/null || echo "")
    fi
fi

# --- Decision: COMPLETE/APPROVED → allow exit ---

if [[ "$ALICE_DECISION" == "COMPLETE" || "$ALICE_DECISION" == "APPROVED" ]]; then
    REASON="alice approved"
    [[ -n "$ALICE_MSG_ID" ]] && REASON="$REASON (msg: $ALICE_MSG_ID)"
    [[ -n "$ALICE_SUMMARY" ]] && REASON="$REASON - $ALICE_SUMMARY"

    # Reset review state - gate turns off after approval
    RESET_MSG=$(jq -n --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{enabled: false, timestamp: $ts}')
    jwz post "$REVIEW_STATE_TOPIC" -m "$RESET_MSG" >/dev/null 2>&1 || true

    jq -n --arg reason "$REASON" '{decision: "approve", reason: $reason}'
    exit 0
fi

# --- Circuit breaker: detect stale review loops ---

# Read circuit breaker state from review:state
LAST_BLOCKED_ID=$(jq -r '.[0].body | fromjson | .last_blocked_review_id // ""' "$JWZ_TMPFILE" 2>/dev/null || echo "")
BLOCK_COUNT=$(jq -r '.[0].body | fromjson | .block_count // 0' "$JWZ_TMPFILE" 2>/dev/null || echo "0")
NO_ID_BLOCK_COUNT=$(jq -r '.[0].body | fromjson | .no_id_block_count // 0' "$JWZ_TMPFILE" 2>/dev/null || echo "0")
# Ensure counters are numeric
[[ "$BLOCK_COUNT" =~ ^[0-9]+$ ]] || BLOCK_COUNT=0
[[ "$NO_ID_BLOCK_COUNT" =~ ^[0-9]+$ ]] || NO_ID_BLOCK_COUNT=0

MAX_BLOCKS=3

# Helper to trip circuit breaker and disable review
trip_circuit_breaker() {
    local msg="$1"
    local reason="$2"

    # Disable review state so user must explicitly re-enable with #idle
    DISABLE_MSG=$(jq -n --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{enabled: false, timestamp: $ts, circuit_breaker_tripped: true}')
    jwz post "$REVIEW_STATE_TOPIC" -m "$DISABLE_MSG" >/dev/null 2>&1 || true

    emit_warning_and_approve "$msg" "$reason"
}

# Helper to persist circuit breaker state (fails open if persistence fails)
persist_breaker_state() {
    local update_msg="$1"
    local context="$2"

    if ! jwz post "$REVIEW_STATE_TOPIC" -m "$update_msg" >/dev/null 2>&1; then
        # Can't persist counter - fail open to prevent infinite loop
        emit_warning_and_approve \
            "Circuit breaker: failed to persist state ($context). Failing open to prevent infinite loop." \
            "Circuit breaker state persistence failed"
    fi
}

# Handle case where ALICE_MSG_ID is empty (review enabled but no alice status)
if [[ -z "$ALICE_MSG_ID" ]]; then
    NEW_NO_ID_COUNT=$((NO_ID_BLOCK_COUNT + 1))

    if [[ $NEW_NO_ID_COUNT -ge $MAX_BLOCKS ]]; then
        trip_circuit_breaker \
            "Circuit breaker: blocked $NEW_NO_ID_COUNT times with no alice review ID. Review enabled but alice status unavailable." \
            "Circuit breaker tripped after $NEW_NO_ID_COUNT blocks with no review ID"
    fi

    UPDATE_MSG=$(jq -n \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson count "$NEW_NO_ID_COUNT" \
        '{enabled: true, timestamp: $ts, no_id_block_count: $count}')
    persist_breaker_state "$UPDATE_MSG" "no_id_block_count=$NEW_NO_ID_COUNT"

# Check if we're re-blocking on the same stale review
elif [[ "$ALICE_MSG_ID" == "$LAST_BLOCKED_ID" ]]; then
    NEW_BLOCK_COUNT=$((BLOCK_COUNT + 1))

    if [[ $NEW_BLOCK_COUNT -ge $MAX_BLOCKS ]]; then
        trip_circuit_breaker \
            "Circuit breaker: blocked $NEW_BLOCK_COUNT times on same review ($ALICE_MSG_ID). Agent may be stuck." \
            "Circuit breaker tripped after $NEW_BLOCK_COUNT blocks on review $ALICE_MSG_ID"
    fi

    UPDATE_MSG=$(jq -n \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg id "$ALICE_MSG_ID" \
        --argjson count "$NEW_BLOCK_COUNT" \
        '{enabled: true, timestamp: $ts, last_blocked_review_id: $id, block_count: $count}')
    persist_breaker_state "$UPDATE_MSG" "block_count=$NEW_BLOCK_COUNT"

else
    # New review ID - reset counters
    UPDATE_MSG=$(jq -n \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg id "$ALICE_MSG_ID" \
        '{enabled: true, timestamp: $ts, last_blocked_review_id: $id, block_count: 1, no_id_block_count: 0}')
    persist_breaker_state "$UPDATE_MSG" "new_review_id=$ALICE_MSG_ID"
fi

# --- Alice hasn't approved → block ---

# Build reason with alice's feedback if available
if [[ "$ALICE_DECISION" == "ISSUES" ]]; then
    REASON="alice found issues that must be addressed."
    [[ -n "$ALICE_MSG_ID" ]] && REASON="$REASON (review: $ALICE_MSG_ID)"
    [[ -n "$ALICE_SUMMARY" ]] && REASON="$REASON

$ALICE_SUMMARY"
    [[ -n "$ALICE_MESSAGE" ]] && REASON="$REASON

alice says: $ALICE_MESSAGE"

    REASON="$REASON

---
If you have already addressed these issues, re-invoke alice for a fresh review.
This review may be stale if you made changes since it was generated."
else
    REASON="Review is enabled but alice hasn't approved. Spawn alice before exiting.

Invoke alice with this prompt format:

---
SESSION_ID=$SESSION_ID

## Work performed

<Include relevant sections based on what you did>

### Context (if you referenced issues or messages):
- tissue issue <id>: <title or summary>
- jwz message <topic>: <what it informed>

### Code changes (if any files were modified):
- <file>: <what changed>

### Research findings (if you explored/investigated):
- <what you searched for>: <what you found or concluded>

### Planning outcomes (if you made or refined a plan):
- <decision or step>: <the outcome>

### Open questions (if you have gaps or uncertainties):
- <question>: <why it matters or what's blocking>
---

RULES:
- Report ALL work you performed, not just code changes
- List facts only (what you did, what you found), no justifications
- Do NOT summarize intent or explain why you chose an approach
- Do NOT editorialize or argue your case
- Include relevant details: files read, searches run, conclusions reached
- Alice forms her own judgment from the user's prompt transcript

Alice will read jwz topic 'user:context:$SESSION_ID' for the user's actual request
and evaluate whether YOUR work satisfies THE USER's desires (not your interpretation)."
fi

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
