#!/bin/bash
# idle SubagentStop hook - enforce second opinion for alice agent
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

# Helper to check if this is alice (deep reasoning agent)
is_alice_agent() {
    # Look for alice-specific output patterns in the last assistant message
    # alice MUST output "## Result" with status and confidence
    local last_text
    # NDJSON parsing: split by newlines, parse each line, filter for assistant messages
    last_text=$(jq -r -Rs '
        split("\n") | .[] | select(length > 0) | fromjson? |
        select(.type == "assistant") | .message.content[]? |
        select(.type == "text") | .text
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || echo "")

    # Check for alice's output format markers
    if echo "$last_text" | grep -qF '**Status**: RESOLVED' || \
       echo "$last_text" | grep -qF '**Status**: NEEDS_INPUT' || \
       echo "$last_text" | grep -qF '**Status**: UNRESOLVED'; then
        return 0  # Is alice
    fi

    # Also check for alice's structured sections
    if echo "$last_text" | grep -qF '## Hypotheses' && echo "$last_text" | grep -qF '## Recommendation'; then
        return 0  # Is alice
    fi

    # Check for quality gate mode (reviewing bob's work)
    if echo "$last_text" | grep -qF 'Verdict: PASS' || echo "$last_text" | grep -qF 'Verdict: REVISE'; then
        return 0  # Is alice in quality gate mode
    fi

    return 1  # Not alice
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
    opinion_content=$(echo "$last_text" | awk '/^## Second Opinion/{found=1; next} /^## /{found=0} found' | head -20)

    if [[ -z "$opinion_content" ]] || echo "$opinion_content" | grep -qiE '^\s*(TODO|TBD|pending|not yet)'; then
        return 1  # Empty or placeholder
    fi

    return 0  # Has valid second opinion
}

# Only enforce for alice agent
if ! is_alice_agent; then
    exit 0
fi

# Check if second opinion was obtained
if ! has_second_opinion; then
    cat >&2 << 'EOF'
[SUBAGENT GATE] Analysis incomplete - second opinion required.

You MUST consult another model before completing the analysis:

1. Run the second opinion command:
   ```bash
   $SECOND_OPINION "You are helping debug/design a software project.

   Problem: [DESCRIBE THE PROBLEM]

   My hypotheses (ranked):
   1. [Most likely]
   2. [Alternative]

   Relevant code: [PASTE KEY SNIPPETS]

   Do you agree? What would you add?

   ---
   End with:
   ---SUMMARY---
   [Your final analysis]
   " > "$STATE_DIR/opinion-1.log" 2>&1
   sed -n '/---SUMMARY---/,$ p' "$STATE_DIR/opinion-1.log"
   ```

2. Read and integrate their findings into your ## Second Opinion section

3. Reconcile any disagreements

4. Then emit your final recommendation

DO NOT skip the second opinion - single-model analysis has blind spots.
EOF
    exit 2
fi

# Second opinion obtained, allow completion
exit 0
