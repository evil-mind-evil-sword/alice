# idle

An outer harness for Claude Code. Long-running loops with alice review gates.

## What It Does

1. **`/loop`** — Iterate on tasks or work through your issue tracker
2. **alice** — Deep reasoning agent called automatically on completion
3. **Hooks** — Stop hook manages loop state, injects alice review

## Install

```sh
/plugin marketplace add evil-mind-evil-sword/marketplace
/plugin install idle@emes
```

## Quick Start

```sh
# Iterate on a task
/loop Add input validation to API endpoints

# Work through issue backlog (requires tissue)
/loop
```

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  /loop "task"                                       │
│       │                                             │
│       ▼                                             │
│  ┌─────────┐                                        │
│  │  Work   │◄────────────────────┐                  │
│  └────┬────┘                     │                  │
│       │                          │                  │
│       ▼                          │                  │
│  Signal COMPLETE                 │                  │
│       │                          │                  │
│       ▼                          │                  │
│  ┌─────────┐    not reviewed     │                  │
│  │  Stop   │─────────────────────┤                  │
│  │  Hook   │                     │                  │
│  └────┬────┘                     │                  │
│       │ reviewed                 │                  │
│       ▼                          │                  │
│  ┌─────────┐    needs work       │                  │
│  │  alice  │─────────────────────┘                  │
│  │ review  │                                        │
│  └────┬────┘                                        │
│       │ approved                                    │
│       ▼                                             │
│     EXIT                                            │
└─────────────────────────────────────────────────────┘
```

**Key flow:**
1. You run `/loop` with a task
2. Claude works, signals `<loop-done>COMPLETE</loop-done>`
3. Stop hook blocks exit, requests alice review
4. alice analyzes the work
5. If approved → loop exits. If not → continue working.

## Commands

| Command | Description |
|---------|-------------|
| `/loop [task]` | With args: iterate on task. Without: work issue backlog |
| `/cancel` | Cancel the active loop |

## Agent

| Agent | Role |
|-------|------|
| `alice` | Deep reasoning, completion review. Read-only. |

alice is automatically invoked when you signal completion. She reviews your work and either approves or requests changes.

## Requirements

| Tool | Required For |
|------|--------------|
| [tissue](https://github.com/femtomc/tissue) | `/loop` issue mode |
| [zawinski](https://github.com/femtomc/zawinski) | Loop state persistence |

## Observability

```sh
idle status        # Human-readable loop state
idle status --json # Machine-readable
```

## Escape Hatches

If stuck in a loop:

```sh
/cancel                    # Graceful cancellation
touch .idle-disabled       # Bypass hooks (remove after)
rm -rf .jwz/               # Nuclear reset
```

## License

AGPL-3.0
