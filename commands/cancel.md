---
description: Cancel the active loop
---

# /cancel

Stop the current loop gracefully.

## What It Does

1. Posts `ABORT` event to jwz
2. Pauses any active issue (if in issue mode)
3. Loop exits on next iteration

## Usage

```
/cancel
```

## Alternative Methods

If `/cancel` doesn't work:

| Method | Command |
|--------|---------|
| File bypass | `touch .idle-disabled` (remove after) |
| Manual abort | `jwz post "loop:current" -m '{"event":"ABORT","stack":[]}'` |
| Full reset | `rm -rf .jwz/` |
