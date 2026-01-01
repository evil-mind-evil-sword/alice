#!/bin/bash
# idle hooks shared utilities
# Source this file in hooks: source "${BASH_SOURCE%/*}/utils.sh"

# Get project name from git remote or directory basename
get_project_name() {
    local cwd="${1:-.}"
    local name=""

    # Try git remote first
    if command -v git &>/dev/null; then
        name=$(git -C "$cwd" remote get-url origin 2>/dev/null | sed -E 's/.*[:/]([^/]+)\/([^/.]+)(\.git)?$/\2/' || true)
    fi

    # Fall back to directory basename
    if [[ -z "$name" ]]; then
        name=$(basename "$(cd "$cwd" && pwd)")
    fi

    echo "$name"
}

# Get current git branch
get_git_branch() {
    local cwd="${1:-.}"
    git -C "$cwd" branch --show-current 2>/dev/null || echo ""
}

# Post to ntfy with rich formatting
# Usage: ntfy_post "title" "body" [priority] [tags]
# Priority: 1=min, 2=low, 3=default, 4=high, 5=urgent
# Tags: comma-separated emoji names (e.g., "rocket,white_check_mark")
ntfy_post() {
    local title="$1"
    local body="$2"
    local priority="${3:-3}"
    local tags="${4:-}"

    # Skip if no topic configured
    local topic="${IDLE_NTFY_TOPIC:-}"
    if [[ -z "$topic" ]]; then
        return 0
    fi

    # Build ntfy URL (support custom server via IDLE_NTFY_SERVER)
    local server="${IDLE_NTFY_SERVER:-https://ntfy.sh}"
    local url="$server/$topic"

    # Build curl args
    local -a args=(
        -s
        -X POST
        -H "Title: $title"
        -H "Priority: $priority"
    )

    if [[ -n "$tags" ]]; then
        args+=(-H "Tags: $tags")
    fi

    args+=(-d "$body" "$url")

    # Post in background to not block hook
    curl "${args[@]}" &>/dev/null &
}

# Format tool availability as checkmarks
format_tool_status() {
    local tool="$1"
    if command -v "$tool" &>/dev/null; then
        echo "✓"
    else
        echo "✗"
    fi
}
