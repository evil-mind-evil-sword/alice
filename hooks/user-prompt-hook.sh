#!/bin/bash
# idle UserPromptSubmit hook
# Captures user messages and stores them in jwz for alice context
#
# Output: JSON (approve to continue)
# Exit 0 always

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract session info and user prompt
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"')
USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

cd "$CWD"

# Store user message to jwz for alice context
if command -v jwz &>/dev/null && [[ -n "$USER_PROMPT" ]]; then
    USER_TOPIC="user:context:$SESSION_ID"
    ALICE_TOPIC="alice:status:$SESSION_ID"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create both topics if they don't exist
    jwz topic new "$USER_TOPIC" 2>/dev/null || true
    jwz topic new "$ALICE_TOPIC" 2>/dev/null || true

    # Reset alice status - new prompt requires new review
    RESET_MSG=$(jq -n \
        --arg ts "$TIMESTAMP" \
        '{decision: "PENDING", summary: "New user prompt received, review required", timestamp: $ts}')
    jwz post "$ALICE_TOPIC" -m "$RESET_MSG" 2>/dev/null || true

    # Create message payload
    MSG=$(jq -n \
        --arg prompt "$USER_PROMPT" \
        --arg ts "$TIMESTAMP" \
        '{type: "user_message", prompt: $prompt, timestamp: $ts}')

    jwz post "$USER_TOPIC" -m "$MSG" 2>/dev/null || true
fi

# Always approve - this hook just captures, doesn't gate
echo '{"decision": "approve"}'
exit 0
