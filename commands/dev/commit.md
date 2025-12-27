---
description: Commit staged changes with a descriptive message
---

# Commit Command

Commit current changes without the full `/work` workflow.

## Usage

```
/commit [message]
```

If no message provided, analyze changes and generate one.

## Pre-check

Verify there are changes to commit:
```bash
git status --short
```

If **no changes**: Report "Nothing to commit" and stop.

## Steps

1. **Check staged changes**:
   ```bash
   git diff --cached --stat
   ```

2. **If nothing staged**, stage all changes:
   ```bash
   git add -A
   ```

3. **Generate commit message** (if not provided):
   - Analyze `git diff --cached`
   - Determine type: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
   - Write concise description (1-2 sentences)

4. **Commit**:
   ```bash
   git commit -m "type: description"
   ```

5. **Report** the commit hash and summary

## Commit Types

- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code restructuring (no behavior change)
- `test` - Adding or updating tests
- `docs` - Documentation only
- `chore` - Build, tooling, dependencies

## Output

```
## Result

**Status**: COMMITTED | NO_CHANGES | FAILED
**Commit**: abc1234
**Summary**: type: description

## Files Changed
- path/to/file.ext (+10, -5)
```
