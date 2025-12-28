---
description: Manage Git worktrees for issues
---

# Worktree Command

Manage idle's Git worktrees for issue isolation.

## Usage

```
/worktree list              # List all idle worktrees
/worktree status            # Show worktree status with dirty/clean
/worktree remove <issue-id> # Remove a worktree (without merging)
/worktree prune             # Remove orphaned worktrees
```

## Subcommands

### list

Show all idle worktrees:
```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
echo "Idle worktrees:"
echo ""

git worktree list | while read -r line; do
    WT_PATH=$(echo "$line" | awk '{print $1}')
    if [[ "$WT_PATH" == *".worktrees/idle/"* ]]; then
        BRANCH=$(echo "$line" | awk '{print $3}' | tr -d '[]')
        ISSUE_ID=$(basename "$WT_PATH")
        echo "  $ISSUE_ID"
        echo "    Path: $WT_PATH"
        echo "    Branch: $BRANCH"
        echo ""
    fi
done
```

### status

Show worktree status with dirty/clean indicators:
```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
echo "Worktree Status:"
echo ""

for WT_DIR in "$REPO_ROOT/.worktrees/idle/"*/; do
    [[ -d "$WT_DIR" ]] || continue
    ISSUE_ID=$(basename "$WT_DIR")

    # Check if dirty (staged or unstaged changes)
    if git -C "$WT_DIR" diff --quiet 2>/dev/null && \
       git -C "$WT_DIR" diff --cached --quiet 2>/dev/null; then
        STATUS="clean"
    else
        STATUS="dirty"
    fi

    # Count commits ahead
    BASE=$(git -C "$WT_DIR" merge-base HEAD main 2>/dev/null || echo "")
    if [[ -n "$BASE" ]]; then
        COMMITS=$(git -C "$WT_DIR" rev-list --count "$BASE"..HEAD)
    else
        COMMITS="?"
    fi

    echo "  $ISSUE_ID: $STATUS ($COMMITS commits)"
done
```

### remove

Remove a worktree without merging:
```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
SAFE_ID=$(printf '%s' "$ARGUMENTS" | tr -cd 'a-zA-Z0-9_-')
BRANCH="idle/issue/$SAFE_ID"
WORKTREE_PATH="$REPO_ROOT/.worktrees/idle/$SAFE_ID"

# Check if worktree exists
if ! git worktree list | grep -qF -- "$WORKTREE_PATH"; then
    echo "Error: No worktree found for $ARGUMENTS"
    exit 1
fi

# Check for uncommitted changes (staged or unstaged)
if ! git -C "$WORKTREE_PATH" diff --quiet 2>/dev/null || \
   ! git -C "$WORKTREE_PATH" diff --cached --quiet 2>/dev/null; then
    echo "Warning: Worktree has uncommitted changes"
    git -C "$WORKTREE_PATH" status --short
    echo ""
    echo "Use --force to remove anyway"
    exit 1
fi

# Remove worktree
git worktree remove "$WORKTREE_PATH"
echo "Removed worktree: $WORKTREE_PATH"

# Optionally delete branch
echo "Branch $BRANCH still exists. Delete with:"
echo "  git branch -D $BRANCH"
```

### prune

Remove orphaned worktrees (worktree directory deleted but still registered):
```bash
echo "Pruning orphaned worktrees..."
git worktree prune -v

# Also clean up empty directories
REPO_ROOT=$(git rev-parse --show-toplevel)
if [[ -d "$REPO_ROOT/.worktrees/idle" ]]; then
    find "$REPO_ROOT/.worktrees/idle" -type d -empty -delete 2>/dev/null || true
fi

echo "Done"
```

## Worktree Locations

Idle worktrees are stored at:
```
<repo-root>/.worktrees/idle/<issue-id>/
```

This directory is automatically added to `.gitignore`.

## Common Tasks

### Check what's in a worktree
```bash
WORKTREE_PATH=$(git worktree list | grep "issue-id" | awk '{print $1}')
git -C "$WORKTREE_PATH" log --oneline -10
git -C "$WORKTREE_PATH" diff --stat
```

### Stash changes in a worktree
```bash
git -C "$WORKTREE_PATH" stash push -m "WIP: issue-id"
```

### Switch to a worktree in terminal
```bash
cd "$REPO_ROOT/.worktrees/idle/issue-id"
```

## Error Recovery

### "fatal: is already checked out"
The branch is checked out in another worktree:
```bash
git worktree list | grep "branch-name"
# Remove the other worktree first
```

### Worktree in bad state
Force remove and recreate:
```bash
git worktree remove --force "$WORKTREE_PATH"
git worktree add -b "$BRANCH" "$WORKTREE_PATH" main
# Don't forget submodules!
git -C "$WORKTREE_PATH" submodule update --init --recursive
```

### Submodules not initialized
If worktree submodules are empty:
```bash
git -C "$WORKTREE_PATH" submodule update --init --recursive
```

### Clean up everything
Nuclear option - remove all idle worktrees:
```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
for WT in "$REPO_ROOT/.worktrees/idle/"*/; do
    git worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
done
git worktree prune
```
