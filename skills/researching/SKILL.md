---
name: researching
description: Comprehensive research with quality gate. Composes bob (research) with alice (review) for source-checked, confidence-calibrated findings. Use when research should be verified and persist.
---

# Researching Skill

Compose bob (fast research) with alice (quality gate) for verified research artifacts.

## When to Use

- Need documented research that persists beyond conversation
- Topic requires source verification and confidence calibration
- Research should be discoverable by other agents via jwz
- High-stakes decisions that need cited evidence

**Don't use for**: Quick lookups where you don't need verification. Just ask naturally and bob will be auto-discovered.

## Composition Pattern

**Review-Gate with Bounded Iteration (max 1 revision)**

```
bob (research) ──→ alice (quality gate)
                        │
               PASS ────┼──── REVISE
                 │             │
               DONE      bob (fix, 1x max)
                               │
                         alice (final gate)
```

- bob produces research with citations
- alice validates quality (not content accuracy - that's bob's job)
- Max 1 revision keeps cost predictable
- Stop conditions: PASS, one revision done, or needs user input

## Quality Rubric (Shared)

Both agents apply this checklist:

| Criterion | Check |
|-----------|-------|
| **Citations** | Every claim has inline citation |
| **Coverage** | Key perspectives included |
| **Recency** | Sources current (≤2 years for APIs) |
| **Confidence** | Not overclaiming; uncertainties stated |
| **Conflicts** | Disagreements noted, not hidden |

## Workflow

### Step 1: Research (bob)

Invoke bob to research the topic:

```
Task(subagent_type="idle:bob", prompt="Research: <topic>")
```

**bob produces**:
- Artifact at `.claude/plugins/idle/bob/<topic>.md`
- Status: FOUND | NOT_FOUND | PARTIAL
- Confidence: HIGH | MEDIUM | LOW
- Sources with credibility ratings
- Findings with inline citations
- Open Questions section
- Self-check against quality rubric

**bob posts to jwz**:
```bash
jwz post "issue:<id>" --role bob \
  -m "[bob] RESEARCH: <topic>
Path: .claude/plugins/idle/bob/<topic>.md
Summary: <finding>
Confidence: HIGH|MEDIUM|LOW
Sources: <count>"
```

### Step 2: Quality Gate (alice)

Invoke alice to review bob's artifact:

```
Task(subagent_type="idle:alice", prompt="Review bob's research at .claude/plugins/idle/bob/<topic>.md using quality gate mode")
```

**alice evaluates**:
- Citation quality (claim-to-source alignment)
- Coverage gaps (missing perspectives)
- Overconfidence (claims without evidence)
- Recency (outdated information)

**alice returns**: **PASS** | **REVISE**

If REVISE, alice provides:
- Required Fixes (blocking) - must address
- Nice-to-Haves (optional) - can skip

**alice posts to jwz**:
```bash
jwz post "issue:<id>" --role alice \
  -m "[alice] REVIEW: bob's <topic> research
Verdict: PASS|REVISE
Required fixes: <count or 'none'>
Notes: <summary>"
```

### Step 3: Revision (if REVISE, max 1x)

Re-invoke bob with alice's required fixes:

```
Task(subagent_type="idle:bob", prompt="Revise research at .claude/plugins/idle/bob/<topic>.md

Alice's required fixes:
- <fix 1>
- <fix 2>

Update the artifact and re-post to jwz.")
```

### Step 4: Final Gate

Re-invoke alice for final review:

```
Task(subagent_type="idle:alice", prompt="Final review of bob's revised research at .claude/plugins/idle/bob/<topic>.md")
```

alice returns:
- **PASS** - Ready to use
- **PASS_WITH_LIMITATIONS** - Usable with noted caveats
- **NEEDS_INPUT** - Unresolvable without user guidance

## Stop Conditions

1. alice returns PASS (or PASS_WITH_LIMITATIONS)
2. One revision cycle completed
3. Issues need user input (scope change, access needed)

## Output

Final deliverables:
- Artifact: `.claude/plugins/idle/bob/<topic>.md`
- jwz thread on `issue:<id>` with research + review history

## Example

```bash
# User asks for OAuth research
# 1. bob researches, writes artifact, posts to jwz
# 2. alice reviews, finds missing PKCE coverage, returns REVISE
# 3. bob revises artifact with PKCE section
# 4. alice re-reviews, returns PASS
# 5. Skill completes with verified artifact
```

## Discovery

Find prior research:
```bash
jwz search "RESEARCH:"
jwz search "REVIEW:" | grep "Verdict: PASS"
ls .claude/plugins/idle/bob/
```
