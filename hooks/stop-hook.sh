#!/bin/bash
# idle stop hook - implements self-referential loops via jwz messaging
# Intercepts Claude's exit to force continuation until task complete

set -e

# Lock file for protecting concurrent jwz operations
LOCK_FILE="${TMPDIR:-/tmp}/idle-loop.lock"

# Acquire lock with timeout (10 seconds)
acquire_lock() {
    local max_wait=100
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if mkdir "$LOCK_FILE" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1  # Failed to acquire lock
}

# Release lock
release_lock() {
    rmdir "$LOCK_FILE" 2>/dev/null || true
}

# Ensure lock is released on any exit (signal or script failure)
trap 'release_lock' EXIT


# Helper function to emit trace events
emit_trace_event() {
    [[ "${IDLE_TRACE:-}" != "1" ]] && return
    local event="$1"
    local details="${2:-{}}"
    local event_id="${RUN_ID:-unknown-$$}-${event}-${ITERATION:-0}"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if ! command -v jwz >/dev/null 2>&1; then
        return
    fi

    # Create topic if it doesn't exist
    jwz topic new "loop:trace" 2>/dev/null || true

    # Build and emit event JSON
    local event_json="{\"event_id\":\"$event_id\",\"ts\":\"$ts\",\"run_id\":\"${RUN_ID:-}\",\"loop_kind\":\"${MODE:-}\",\"event\":\"$event\",\"iteration\":${ITERATION:-0},\"max\":${MAX_ITERATIONS:-0},\"details\":$details}"
    jwz post "loop:trace" -m "$event_json" 2>/dev/null || true
}

# Read hook input from stdin
INPUT=$(cat)

# Extract session info
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Change to project directory
if [[ -n "$CWD" ]]; then
    cd "$CWD"
fi

# Environment variable escape hatch
if [[ "${IDLE_LOOP_DISABLE:-}" == "1" ]]; then
    exit 0
fi

# State file fallback location
STATE_FILE=".claude/idle-loop.local.md"

# Try to read loop state from jwz first
STATE=""
if command -v jwz >/dev/null 2>&1 && [[ -d .jwz ]]; then
    # Acquire lock before reading jwz state
    if acquire_lock; then
        # Get the latest message from loop:current topic
        STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
        release_lock
    else
        # Lock acquisition failed - wait briefly and try fallback
        echo "Warning: Could not acquire lock on jwz state, using fallback" >&2
    fi
fi

# Parse state (either from jwz JSON or fallback to state file)
if [[ -n "$STATE" ]] && echo "$STATE" | jq -e '.schema' >/dev/null 2>&1; then
    # jwz JSON state
    STACK_LEN=$(echo "$STATE" | jq -r '.stack | length')

    if [[ "$STACK_LEN" == "0" ]] || [[ -z "$STACK_LEN" ]]; then
        # No active loop
        exit 0
    fi

    # Check for ABORT event
    EVENT=$(echo "$STATE" | jq -r '.event // "STATE"')
    if [[ "$EVENT" == "ABORT" ]]; then
        exit 0
    fi

    # Check staleness (2 hour TTL) - use UTC for both timestamps
    UPDATED_AT=$(echo "$STATE" | jq -r '.updated_at // empty')
    if [[ -n "$UPDATED_AT" ]]; then
        UPDATED_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${UPDATED_AT%Z}" +%s 2>/dev/null || \
                     date -u -d "$UPDATED_AT" +%s 2>/dev/null || echo 0)
        NOW_TS=$(date -u +%s)
        AGE=$((NOW_TS - UPDATED_TS))
        if [[ $AGE -gt 7200 ]]; then
            echo "Warning: Loop state is stale ($AGE seconds old), allowing exit" >&2
            emit_trace_event "STALENESS" "{\"age\":$AGE}"
            exit 0
        fi
    fi

    # Get top of stack (current loop frame)
    TOP=$(echo "$STATE" | jq -r '.stack[-1]')
    MODE=$(echo "$TOP" | jq -r '.mode')
    ITERATION=$(echo "$TOP" | jq -r '.iter')
    MAX_ITERATIONS=$(echo "$TOP" | jq -r '.max')
    PROMPT_FILE=$(echo "$TOP" | jq -r '.prompt_file // empty')
    RUN_ID=$(echo "$STATE" | jq -r '.run_id')

    # Worktree context (for issue mode)
    WORKTREE_PATH=$(echo "$TOP" | jq -r '.worktree_path // empty')
    BRANCH=$(echo "$TOP" | jq -r '.branch // empty')
    ISSUE_ID=$(echo "$TOP" | jq -r '.issue_id // empty')

    USE_JWZ=true

    # Emit LOOP_START on first iteration
    if [[ "$ITERATION" -eq 0 ]]; then
        emit_trace_event "LOOP_START"
    fi
else
    # Fallback to state file
    if [[ ! -f "$STATE_FILE" ]]; then
        exit 0
    fi

    # Parse YAML frontmatter
    parse_yaml_value() {
        local key="$1"
        sed -n '/^---$/,/^---$/p' "$STATE_FILE" | grep "^${key}:" | sed "s/^${key}: *//"
    }

    ACTIVE=$(parse_yaml_value "active")
    if [[ "$ACTIVE" != "true" ]]; then
        rm -f "$STATE_FILE"
        exit 0
    fi

    MODE=$(parse_yaml_value "mode")
    ITERATION=$(parse_yaml_value "iteration")
    MAX_ITERATIONS=$(parse_yaml_value "max_iterations")
    PROMPT_FILE=""

    USE_JWZ=false

    # Emit LOOP_START on first iteration (fallback path)
    if [[ "$ITERATION" -eq 0 ]]; then
        emit_trace_event "LOOP_START"
    fi
fi

# Validate numeric values
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]] || ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "Warning: Corrupted loop state, cleaning up" >&2
    emit_trace_event "ABORT" "{\"reason\":\"corrupted_state\"}"
    if [[ "$USE_JWZ" == "true" ]]; then
        # Acquire lock before writing state
        if acquire_lock; then
            jwz post "loop:current" -m '{"schema":1,"event":"ABORT","stack":[]}'
            release_lock
        fi
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# Check if max iterations reached
if [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    emit_trace_event "MAX_ITERATIONS"
    if [[ "$USE_JWZ" == "true" ]]; then
        # Acquire lock before writing state
        if acquire_lock; then
            jwz post "loop:current" -m '{"schema":1,"event":"DONE","reason":"MAX_ITERATIONS","stack":[]}'
            release_lock
        fi
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# Read transcript and check for completion signals
COMPLETION_FOUND=false
COMPLETION_REASON=""

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
    # Get last assistant message using slurp mode to handle long transcripts
    # Load entire file at once and find the last assistant message reliably
    LAST_MESSAGE=$(jq -r -Rs 'split("\n") | .[] | select(length > 0) | fromjson? | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

    # Check for completion signals based on mode
    # Only match completion markers at the start of a line (not indented or in code blocks)
    # Use grep with ^ anchor to reject indented markers in code blocks
    case "$MODE" in
        loop)
            if printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>COMPLETE</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>MAX_ITERATIONS</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ITERATIONS"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>STUCK</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="STUCK"
            fi
            ;;
        issue)
            if printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>COMPLETE</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>MAX_ITERATIONS</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ITERATIONS"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<loop-done>STUCK</loop-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="STUCK"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<issue-complete>DONE</issue-complete>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="COMPLETE"
            fi
            ;;
        grind)
            if printf '%s' "$LAST_MESSAGE" | grep -qE '^<grind-done>NO_MORE_ISSUES</grind-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="NO_MORE_ISSUES"
            elif printf '%s' "$LAST_MESSAGE" | grep -qE '^<grind-done>MAX_ISSUES</grind-done>$'; then
                COMPLETION_FOUND=true
                COMPLETION_REASON="MAX_ISSUES"
            fi
            # For grind, <issue-complete> means pop issue frame, not exit grind
            ;;
    esac
fi

# If completion signal found, verify review requirements before allowing exit
if [[ "$COMPLETION_FOUND" == "true" ]]; then
    # REVIEW GATE: For issue/grind with COMPLETE, verify review was done
    # NOTE: Review gate only applies when using jwz (worktrees require jwz)
    REVIEW_REQUIRED=false
    REVIEW_PASSED=true
    REVIEW_ESCALATE=false

    if [[ "$USE_JWZ" == "true" ]] && [[ "$COMPLETION_REASON" == "COMPLETE" ]] && [[ -n "$WORKTREE_PATH" ]] && [[ -d "$WORKTREE_PATH" ]]; then
        REVIEW_REQUIRED=true

        # Re-read state with lock to avoid race conditions
        if acquire_lock; then
            STATE=$(jwz read "loop:current" 2>/dev/null | tail -1 || true)
            TOP=$(echo "$STATE" | jq -r '.stack[-1]')
            release_lock
        fi

        # Get review tracking state from fresh TOP
        LAST_REVIEWED_SHA=$(echo "$TOP" | jq -r '.last_reviewed_sha // empty')
        REVIEW_ITER=$(echo "$TOP" | jq -r '.review_iter // 0')
        LAST_REVIEW_STATUS=$(echo "$TOP" | jq -r '.last_review_status // empty')

        # Validate REVIEW_ITER is numeric
        if ! [[ "$REVIEW_ITER" =~ ^[0-9]+$ ]]; then
            REVIEW_ITER=0
        fi

        # Get current HEAD (handle failure gracefully)
        CURRENT_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD 2>/dev/null || echo "")
        if [[ -z "$CURRENT_SHA" ]]; then
            REVIEW_PASSED=false
            REVIEW_BLOCK_REASON="Cannot determine HEAD in worktree. Check worktree state."
        fi

        # Check for uncommitted changes
        HAS_CHANGES=false
        if ! git -C "$WORKTREE_PATH" diff --quiet 2>/dev/null || \
           ! git -C "$WORKTREE_PATH" diff --cached --quiet 2>/dev/null; then
            HAS_CHANGES=true
        fi

        # Determine if review gate passes (explicit LGTM required)
        if [[ -n "$CURRENT_SHA" ]]; then
            if [[ "$HAS_CHANGES" == "true" ]]; then
                # Uncommitted changes = cannot complete
                REVIEW_PASSED=false
                REVIEW_BLOCK_REASON="Uncommitted changes exist. Commit and run /review before completing."
            elif [[ -z "$LAST_REVIEWED_SHA" ]]; then
                # Never reviewed = cannot complete
                REVIEW_PASSED=false
                REVIEW_BLOCK_REASON="Code has not been reviewed. Run /review before completing."
            elif [[ "$CURRENT_SHA" != "$LAST_REVIEWED_SHA" ]]; then
                # Commits after review = cannot complete
                REVIEW_PASSED=false
                REVIEW_BLOCK_REASON="Commits made after last review. Run /review before completing."
            elif [[ "$LAST_REVIEW_STATUS" != "LGTM" ]]; then
                # Require explicit LGTM (not just absence of CHANGES_REQUESTED)
                if [[ "$LAST_REVIEW_STATUS" == "CHANGES_REQUESTED" ]]; then
                    if [[ "$REVIEW_ITER" -ge 3 ]]; then
                        # Max review iterations reached - allow completion but require follow-up issues
                        REVIEW_PASSED=true
                        REVIEW_ESCALATE=true
                    else
                        REVIEW_PASSED=false
                        REVIEW_BLOCK_REASON="Last review requested changes. Address feedback and run /review again. (Review iteration $REVIEW_ITER/3)"
                    fi
                else
                    # Unknown or empty status - require explicit LGTM
                    REVIEW_PASSED=false
                    REVIEW_BLOCK_REASON="Review status unclear (got: '$LAST_REVIEW_STATUS'). Run /review to get explicit LGTM."
                fi
            fi
            # If none of the above triggered, REVIEW_PASSED remains true (LGTM at current SHA)
        fi
    fi

    # Check for escalation (review limit exceeded, must create follow-up issues)
    if [[ "${REVIEW_ESCALATE:-false}" == "true" ]]; then
        emit_trace_event "REVIEW_ESCALATE" "{\"review_iter\":$REVIEW_ITER}"
        # Allow completion but inject guidance about follow-up issues
        # The grind.md documentation specifies creating issues tagged review-followup
    fi

    # If review gate fails, reject completion and continue loop
    if [[ "$REVIEW_REQUIRED" == "true" ]] && [[ "$REVIEW_PASSED" != "true" ]]; then
        # Escape reason for JSON trace event using jq's @json for proper escaping
        ESCAPED_BLOCK_REASON=$(printf '%s' "$REVIEW_BLOCK_REASON" | jq -Rs '@json')
        emit_trace_event "REVIEW_GATE_BLOCKED" "{\"reason\":$ESCAPED_BLOCK_REASON}"

        # Continue the loop instead of allowing exit
        NEW_ITERATION=$((ITERATION + 1))
        NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        if [[ "$USE_JWZ" == "true" ]]; then
            if acquire_lock; then
                NEW_STACK=$(echo "$STATE" | jq --argjson iter "$NEW_ITERATION" '.stack[-1].iter = $iter')
                jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$(echo "$NEW_STACK" | jq -c '.stack')}"
                release_lock
            fi
        else
            # Fallback path: update state file iteration
            TEMP_FILE=$(mktemp)
            sed "s/^iteration: .*/iteration: $NEW_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
            mv "$TEMP_FILE" "$STATE_FILE"
        fi

        # Build rejection message with inline worktree context
        GATE_WORKTREE_CTX=""
        if [[ -n "$WORKTREE_PATH" ]]; then
            GATE_WORKTREE_CTX="

WORKTREE: $WORKTREE_PATH
BRANCH: $BRANCH
ISSUE: $ISSUE_ID"
        fi

        REASON="[REVIEW GATE] Completion rejected. $REVIEW_BLOCK_REASON

ITERATION $NEW_ITERATION/$MAX_ITERATIONS - You must complete review before marking done.

Workflow:
1. Commit all changes
2. Run /review
3. If CHANGES_REQUESTED: fix issues, commit, run /review again
4. When LGTM: then emit completion signal$GATE_WORKTREE_CTX"

        ESCAPED_REASON=$(printf '%s' "$REASON" | jq -Rs '.')
        cat <<EOF
{
  "decision": "block",
  "reason": $ESCAPED_REASON
}
EOF
        exit 2
    fi

    emit_trace_event "COMPLETION" "{\"reason\":\"$COMPLETION_REASON\"}"
    if [[ "$USE_JWZ" == "true" ]]; then
        # Acquire lock before modifying state
        if acquire_lock; then
            # Pop the completed frame from stack
            NEW_STACK=$(echo "$STATE" | jq '.stack[:-1]')
            STACK_LEN=$(echo "$NEW_STACK" | jq 'length')

            if [[ "$STACK_LEN" == "0" ]]; then
                # All loops complete
                jwz post "loop:current" -m "{\"schema\":1,\"event\":\"DONE\",\"reason\":\"$COMPLETION_REASON\",\"stack\":[]}"
            else
                # Pop frame, continue outer loop
                NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$NEW_STACK}"
                # Don't exit - let outer loop continue
                # Actually, for now we allow exit and let the outer loop re-invoke
            fi
            release_lock
        fi
    else
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# No completion signal found - continue the loop

# Increment iteration counter
NEW_ITERATION=$((ITERATION + 1))
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ "$USE_JWZ" == "true" ]]; then
    # Acquire lock before updating state
    if acquire_lock; then
        # Update top of stack with new iteration
        NEW_STACK=$(echo "$STATE" | jq --argjson iter "$NEW_ITERATION" '.stack[-1].iter = $iter')
        jwz post "loop:current" -m "{\"schema\":1,\"event\":\"STATE\",\"run_id\":\"$RUN_ID\",\"updated_at\":\"$NOW\",\"stack\":$(echo "$NEW_STACK" | jq -c '.stack')}"
        release_lock
    fi
    emit_trace_event "ITERATION"
else
    # Update state file (atomic via temp + mv)
    TEMP_FILE=$(mktemp)
    sed "s/^iteration: .*/iteration: $NEW_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
    emit_trace_event "ITERATION"
    mv "$TEMP_FILE" "$STATE_FILE"
fi

# Get original prompt
if [[ -n "$PROMPT_FILE" ]] && [[ -f "$PROMPT_FILE" ]]; then
    ORIGINAL_PROMPT=$(cat "$PROMPT_FILE")
elif [[ "$USE_JWZ" != "true" ]] && [[ -f "$STATE_FILE" ]]; then
    # Extract from state file (everything after second ---)
    ORIGINAL_PROMPT=$(sed -n '/^---$/,/^---$/!p' "$STATE_FILE" | tail -n +1)
else
    ORIGINAL_PROMPT="Continue working on the task."
fi

# Build worktree context if available
WORKTREE_CONTEXT=""
PHASE_CONTEXT=""
if [[ -n "$WORKTREE_PATH" ]] && [[ -d "$WORKTREE_PATH" ]]; then
    WORKTREE_CONTEXT="

WORKTREE CONTEXT:
- Working directory: $WORKTREE_PATH
- Branch: $BRANCH
- Issue: $ISSUE_ID

IMPORTANT: All file operations must use absolute paths under $WORKTREE_PATH
- Read/Write/Edit: Use absolute paths like $WORKTREE_PATH/src/file.py
- Bash commands: Start with cd \"$WORKTREE_PATH\" && ...
- tissue commands: Run from main repo only (not worktree)"

    # Derive phase from git state
    LAST_REVIEWED_SHA=$(echo "$TOP" | jq -r '.last_reviewed_sha // empty')

    # Check for uncommitted changes
    HAS_CHANGES=false
    if ! git -C "$WORKTREE_PATH" diff --quiet 2>/dev/null || \
       ! git -C "$WORKTREE_PATH" diff --cached --quiet 2>/dev/null; then
        HAS_CHANGES=true
    fi

    CURRENT_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD 2>/dev/null || echo "")

    if [[ "$HAS_CHANGES" == "true" ]]; then
        PHASE="implement"
        PHASE_CONTEXT="
PHASE: implement
ACTION: Changes pending. When implementation complete, run /review before marking done."
    elif [[ -z "$LAST_REVIEWED_SHA" ]] || [[ "$CURRENT_SHA" != "$LAST_REVIEWED_SHA" ]]; then
        PHASE="review_pending"
        PHASE_CONTEXT="
PHASE: review_pending
ACTION REQUIRED: Run /review before emitting <issue-complete>DONE</issue-complete>"
    else
        PHASE="reviewed"
        PHASE_CONTEXT="
PHASE: reviewed
STATUS: Changes reviewed. Ready to complete if implementation is done."
    fi

    # Add agent awareness
    PHASE_CONTEXT="$PHASE_CONTEXT

AGENTS: If stuck on a design decision, consult idle:oracle. After changes, use /review or idle:reviewer."
fi

# Build continuation message
REASON="[ITERATION $NEW_ITERATION/$MAX_ITERATIONS] Continue working on the task. Check your progress and either complete the task or keep iterating.$WORKTREE_CONTEXT$PHASE_CONTEXT"

# Escape for JSON
ESCAPED_REASON=$(printf '%s' "$REASON" | jq -Rs '.')

# Output block decision (exit code 2 = block)
cat <<EOF
{
  "decision": "block",
  "reason": $ESCAPED_REASON
}
EOF

exit 2
