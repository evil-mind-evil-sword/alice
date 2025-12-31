# idle

Quality gate for Claude Code.

Every exit requires alice review. No issues = exit allowed.

## How It Works

```
Agent works → Stop hook → "invoke alice" → alice reviews → issues? → block/allow
```

1. **Stop hook** directs agent to invoke alice via Task tool
2. **alice** reviews the work, creates `alice-review` issues for problems
3. **SubagentStop** detects alice completion, posts status to jwz
4. **No issues** = exit allowed. **Issues exist** = blocked until fixed.

## Install

```sh
curl -fsSL https://github.com/evil-mind-evil-sword/idle/releases/latest/download/install.sh | sh
```

## Skills

| Skill | Purpose |
|-------|---------|
| reviewing | Multi-model second opinions |
| researching | Cited research with verification |
| issue-tracking | Work tracking via tissue |
| technical-writing | Multi-layer document review |
| bib-managing | Bibliography curation |

## Dependencies

- `claude` - Claude Code CLI
- `tissue` - Issue tracking

## License

AGPL-3.0
