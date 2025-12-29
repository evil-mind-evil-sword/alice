#!/bin/bash
# idle SubagentStop hook - enforce second opinion for reviewer agent
#
# Exit codes:
#   0 - Allow completion
#   2 - Block completion, show stderr to subagent and continue
#   Other - Show stderr to user, allow completion

set -e

# Read hook input from stdin
INPUT=$(cat)

# Extract relevant fields
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Change to project directory if available
if [[ -n "$CWD" ]]; then
    cd "$CWD"
fi

# No transcript = can't check, allow completion
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

# Helper to check if this is a reviewer agent
is_reviewer_agent() {
    # Look for reviewer-specific output patterns in the last assistant message
    # The reviewer MUST output "## Result" with "LGTM" or "CHANGES_REQUESTED"
    local last_text
    # NDJSON parsing: split by newlines, parse each line, filter for assistant messages
    last_text=$(jq -r -Rs '
        split("\n") | .[] | select(length > 0) | fromjson? |
        select(.type == "assistant") | .message.content[]? |
        select(.type == "text") | .text
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || echo "")

    # Check for reviewer output format markers (use word boundaries to avoid code block false positives)
    if echo "$last_text" | grep -qF '**Status**: LGTM' || echo "$last_text" | grep -qF '**Status**: CHANGES_REQUESTED'; then
        return 0  # Is reviewer
    fi

    # Also check for reviewer's structured sections (require markdown header format)
    if echo "$last_text" | grep -qF '## Issues' && echo "$last_text" | grep -qF '## Praise'; then
        return 0  # Is reviewer
    fi

    return 1  # Not reviewer
}

# Helper to check if second opinion was obtained
has_second_opinion() {
    # Strategy 1: Look for codex/claude -p invocation in Bash tool calls
    # NDJSON parsing: split by newlines, parse each line
    local codex_call
    codex_call=$(jq -r -Rs '
        split("\n") | .[] | select(length > 0) | fromjson? |
        select(.type == "assistant") | .message.content[]? |
        select(.type == "tool_use") | select(.name == "Bash") |
        .input.command // ""
    ' "$TRANSCRIPT_PATH" 2>/dev/null | grep -E 'codex exec|claude -p' | head -1 || echo "")

    if [[ -z "$codex_call" ]]; then
        return 1  # No codex/claude call found
    fi

    # Strategy 2: Look for "## Second Opinion" section in output
    local last_text
    last_text=$(jq -r -Rs '
        split("\n") | .[] | select(length > 0) | fromjson? |
        select(.type == "assistant") | .message.content[]? |
        select(.type == "text") | .text
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || echo "")

    if ! echo "$last_text" | grep -qF "## Second Opinion"; then
        return 1  # No second opinion section
    fi

    # Strategy 3: Check that second opinion section has content (not just placeholder)
    local opinion_content
    # Extract section content (between ## Second Opinion and next ## or end)
    # Use awk for cleaner section extraction
    opinion_content=$(echo "$last_text" | awk '/^## Second Opinion/{found=1; next} /^## /{found=0} found' | head -20)

    if [[ -z "$opinion_content" ]] || echo "$opinion_content" | grep -qiE '^\s*(TODO|TBD|pending|not yet)'; then
        return 1  # Empty or placeholder
    fi

    return 0  # Has valid second opinion
}

# Only enforce for reviewer agent
if ! is_reviewer_agent; then
    exit 0
fi

# Check if second opinion was obtained
if ! has_second_opinion; then
    cat >&2 << 'EOF'
[SUBAGENT GATE] Review incomplete - second opinion required.

You MUST consult another model before completing the review:

1. Run the second opinion command:
   ```bash
   $SECOND_OPINION "You are reviewing code changes.

   INTENT: [What the change is trying to accomplish]

   Diff to review:
   $(git diff)
   $(git diff --cached)

   Review for: correctness, security, tests, style

   ---
   End with:
   ---SUMMARY---
   [List each issue: type - file:line - description]
   " > "$STATE_DIR/opinion-1.log" 2>&1
   sed -n '/---SUMMARY---/,$ p' "$STATE_DIR/opinion-1.log"
   ```

2. Read and integrate their findings into your ## Second Opinion section

3. Reconcile any disagreements in ## Disputed section

4. Then emit your final verdict

DO NOT skip the second opinion - single-model reviews miss bugs.
EOF
    exit 2
fi

# Second opinion obtained, allow completion
exit 0
