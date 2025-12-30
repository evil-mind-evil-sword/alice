---
name: researching
description: Comprehensive research with orchestrated workers and quality gate. Bob decomposes tasks, spawns charlie workers in parallel, synthesizes results, and routes to alice for review. Use for complex research that should be verified and persist.
---

# Researching Skill

Orchestrated research with parallel workers and quality gate.

## When to Use

- Complex research requiring multiple sub-queries
- Need documented research that persists beyond conversation
- Topic requires source verification and confidence calibration
- Research should be discoverable by other agents via jwz
- High-stakes decisions that need cited evidence

**Don't use for**: Quick lookups. Just ask naturally.

## Agent Roles

| Agent | Role | Model |
|-------|------|-------|
| **bob** | Orchestrator - decomposes, dispatches, synthesizes | opus |
| **charlie** | Worker - executes focused queries | haiku |
| **alice** | Quality gate - reviews synthesis | opus |

## Composition Pattern

```
bob (orchestrator)
 ├─→ charlie (worker) ──→ jwz ──┐
 ├─→ charlie (worker) ──→ jwz ──┼─→ bob (synthesize) ──→ alice (review)
 └─→ charlie (worker) ──→ jwz ──┘
```

**Bounds**: MAX_DEPTH=3, MAX_WORKERS=10

## Quality Rubric (Shared)

| Criterion | Check |
|-----------|-------|
| **Citations** | Every claim has inline citation |
| **Coverage** | Key perspectives included |
| **Recency** | Sources current (≤2 years for APIs) |
| **Confidence** | Not overclaiming; uncertainties stated |
| **Conflicts** | Disagreements noted, not hidden |

## Workflow

### Step 1: Orchestrate (bob)

Invoke bob to orchestrate research:

```
Task(subagent_type="idle:bob", prompt="Research: <topic>

Decompose into focused sub-queries and dispatch charlie workers.
Synthesize findings into a coherent artifact.")
```

**bob does**:
1. Decomposes topic into 3-5 focused queries
2. Spawns charlie workers in parallel via `claude -p`
3. Workers post findings to jwz topic
4. Collects and synthesizes results
5. Validates citations with bibval
6. Writes artifact to `.claude/plugins/idle/bob/<topic>.md`

**bob posts to jwz**:
```bash
jwz post "research:<run_id>" --role bob \
  -m "[bob] SYNTHESIS: <topic>
Path: .claude/plugins/idle/bob/<topic>.md
Workers: <N> dispatched, <M> succeeded
Confidence: HIGH|MEDIUM|LOW"
```

### Step 2: Quality Gate (alice)

Invoke alice to review bob's synthesis:

```
Task(subagent_type="idle:alice", prompt="Review bob's research synthesis at .claude/plugins/idle/bob/<topic>.md

Check:
- Worker coverage adequate?
- Synthesis accurately represents findings?
- Citations properly attributed?
- Conflicts handled appropriately?")
```

**alice returns**: **PASS** | **REVISE**

If REVISE, alice provides Required Fixes.

### Step 3: Revision (if REVISE, max 1x)

Re-invoke bob with alice's fixes:

```
Task(subagent_type="idle:bob", prompt="Revise synthesis at .claude/plugins/idle/bob/<topic>.md

Alice's required fixes:
- <fix 1>
- <fix 2>

May spawn additional charlie workers if needed.")
```

### Step 4: Final Gate

Re-invoke alice for final review.

## Stop Conditions

1. alice returns PASS
2. One revision cycle completed
3. Issues need user input

## Output

- Artifact: `.claude/plugins/idle/bob/<topic>.md`
- jwz thread with orchestration log + review history
- Worker findings preserved in jwz

## Example

```
User: "Research authentication best practices for APIs"

bob (orchestrator):
 ├─→ charlie: "JWT validation" → FOUND (HIGH)
 ├─→ charlie: "OAuth PKCE flow" → FOUND (HIGH)
 ├─→ charlie: "Session security" → FOUND (MEDIUM)
 └─→ charlie: "Rate limiting" → FOUND (HIGH)

bob synthesizes → artifact

alice reviews → REVISE (missing token refresh)

bob spawns:
 └─→ charlie: "Token refresh patterns" → FOUND

bob updates synthesis → artifact v2

alice reviews → PASS
```

## Discovery

```bash
jwz search "SYNTHESIS:"
jwz search "FINDING:"
jwz search "REVIEW:" | grep "Verdict: PASS"
ls .claude/plugins/idle/bob/
```
