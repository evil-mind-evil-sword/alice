# ADR-002: Control-plane Architecture

**Status:** Accepted

## Context

The idle project is a Claude Code plugin providing multi-model development agents. It uses hooks (stop-hook.sh) to implement self-referential loops that intercept Claude's exit to continue tasks.

State is managed via jwz (zawinski), a topic-based messaging CLI. Loop state is stored as JSON in the loop:current topic. The plugin also posts traces to loop:trace for debugging.

A control-plane is needed to:
1. Monitor live loop state
2. Display the execution stack
3. (Future) Send control commands to running agents

The architectural question: How should this TUI/controller be implemented?

## Decision

Implement the control plane as a **separate Zig binary** with on-demand CLI invocation.

The controller runs as `idle status` and reads state from jwz topics.

## Rationale

- **Aligns with roadmap**: Phase 2 plans include a Zig state machine for loop control
- **Native TUI**: termcat library provides rich terminal UI primitives
- **On-demand simplicity**: Avoids daemon complexity while enabling monitoring
- **Persistence via jwz**: State survives between controller invocations

## Alternatives Considered

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **Separate binary (Zig)** - CHOSEN | Better UX via native TUI libs (termcat); single binary distribution; can invoke jwz directly | Requires separate installation |
| **Embedded in plugin** | Easier distribution (bundled with plugin) | Limited by Claude Code plugin model; no native TUI capabilities |
| **Daemon** | Continuous monitoring; automatic crash recovery | Added complexity; security concerns; continuous resource usage |
| **Hook-invoked** | Simple; no separate process | Only runs during Claude sessions; cannot handle out-of-session crashes |

## Consequences

### Positive
- Rich, responsive terminal interface with auto-refresh
- Clean separation from plugin - controller can be updated independently
- On-demand avoids daemon stability/security pitfalls
- State persists via jwz even when controller is closed

### Negative
- Users must build/install Zig binary separately
- Asynchronous state display (eventually consistent via jwz)

## Interaction Protocol

Communication between plugin and controller uses jwz topics:

### Plugin -> jwz
The plugin posts state to loop:current:
```bash
jwz post "loop:current" -m '{"schema":1,"event":"STATE","run_id":"loop-xxx","stack":[...]}'
```

The plugin posts traces to loop:trace:
```bash
jwz post "loop:trace" -m '{"event":"ITERATION","iter":5,"mode":"grind"}'
```

### Controller -> jwz
The controller reads state:
```bash
jwz read loop:current --json
```

### Future: Controller -> Plugin
Control messages via loop:control topic:
```bash
jwz post "loop:control" -m '{"command":"PAUSE"}'
```

## State Schema

Loop state stored in loop:current topic:

```json
{
  "schema": 1,
  "event": "STATE",
  "run_id": "loop-1703123456-12345",
  "updated_at": "2024-12-21T10:30:00Z",
  "stack": [
    {
      "id": "grind-1703123456-12345",
      "mode": "grind",
      "iter": 3,
      "max": 100,
      "prompt_file": "/tmp/idle-grind-xxx/prompt.txt"
    }
  ]
}
```

## Prototype Location

The TUI implementation will reside in:
```
tui/
├── build.zig       # Build configuration
└── src/
    ├── main.zig    # CLI entry point (idle status)
    └── status.zig  # JSON parsing and display
```
