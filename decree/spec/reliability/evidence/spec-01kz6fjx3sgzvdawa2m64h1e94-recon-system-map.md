---
date: '2026-08-04'
governs:
- CLAUDE.md
- docs/CLAUDE.md
- docs/system-map.html
- tools/CLAUDE.md
- tools/check-coherence.sh
- tools/render-system-map.py
- tools/test-system-map.sh
id: SPEC-01KZ6FJX3SGZVDAWA2M64H1E94
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
- SPEC-01KZ5TE6QP704T8G2HJNXSP58W
- SPEC-01KZ6BVHVD97DS1GXK3XZMB1S7
status: implemented
---

# SPEC-01KZ6FJX3SGZVDAWA2M64H1E94 Recon System Map

## Overview

The shipped Recon runtime, the repository-only replay laboratory, and the
repository-only improvement loop each have authoritative state and artifact
contracts. Their individual documents are detailed, but a maintainer currently
has to infer how the three systems connect. That ambiguity produced the
observed ATT-4845 follow-up confusion on 2026-08-04: a scored laboratory run
was mistaken for a live plugin run, and the improvement-loop state was not
distinguished from a ticket workspace state.

**Falsifiable claim:** a generated system map will let a maintainer identify
the current layer, state, input, output, owner, and next action for ATT-4845
without using chat history. Its factual references and rendered bytes will be
checked against their authoritative sources.

**Non-claims:** the map does not change runtime state transitions, triage
quality, replay scoring, or release policy. It does not claim that ATT-4845 is
solved; the current improvement state remains `AWAITING_CANDIDATE` until a
candidate is implemented and evaluated.

## Technical Design

`docs/system-map.html` is a generated repository-level explainer, not a new
runtime surface. It presents three explicitly separated lanes:

1. **Shipped Recon runtime:** Jira ticket and read-only repository input,
   workspace/triage/discovery/routing/gate outputs, and the two STOP paths.
2. **Replay laboratory:** frozen case and skill snapshot input, PREPARED →
   SUBMITTED → SCORED state, fresh-context boundary, and retained score output.
3. **Improvement loop:** durable baseline/candidate/control evidence,
   attempt lifecycle, explicit comparison/review decision, and current
   state-derived next action.

The map uses source links for every lane and distinguishes an artifact's owner
from the generated visual that explains it. It shows concrete ATT-4845 and
RCTRL-1 examples, but no hidden oracle content.

`tools/render-system-map.py` owns the HTML. It resolves source-line references
and SHA-256 fingerprints from `pipeline.md`, the replay and improvement skills,
the improvement contract/brief, frozen public inputs, and current
`improvement-cycle.py state` output. `--check` renders in memory and fails if
any source, state output, reference line, or HTML byte drifts. The generator
does not make external calls or mutate evidence.

`tools/test-system-map.sh` verifies required three-lane content, state labels,
source references, current command output, no hidden-oracle link, narrow/print
responsive rules, and render-byte drift. `check-coherence.sh` runs both checks.

## Testing Strategy

Run the map-specific structural test and renderer byte check. Then run adapter,
link, coherence, and Decree validation. The map-specific test must deliberately
tamper with a disposable rendered copy or source expectation and assert the
intended non-zero diagnostic; it must not alter retained improvement evidence.

## Acceptance Criteria

- [x] One generated map separates runtime, laboratory, and improvement-loop
  states with inputs, outputs, owners, STOP boundaries, and links.
- [x] ATT-4845 and RCTRL-1 appear only as concrete public examples; no oracle
  is linked or embedded.
- [x] Current improvement state is source-derived and shows the same next
  action as `improvement-cycle.py state`.
- [x] Source line references, SHA-256 fingerprints, HTML bytes, and required
  responsive/structural content are drift-checked.
- [x] Coherence, links, adapter, and Decree checks pass.
