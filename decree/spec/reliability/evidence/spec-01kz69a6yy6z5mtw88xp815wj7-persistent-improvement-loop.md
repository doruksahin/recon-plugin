---
date: '2026-08-04'
governs:
- evals/CLAUDE.md
- evals/skills/recon-improvement-loop/SKILL.md
- evals/evidence/
- tools/improvement-cycle.py
- tools/test-improvement-cycle.sh
- tools/CLAUDE.md
- docs/improvement-proposals/README.md
- docs/improvement-proposals/0.22.0/README.md
- docs/improvement-proposals/0.22.0/requirement-closure-coverage/
id: SPEC-01KZ69A6YY6Z5MTW88XP815WJ7
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ69A6YY6Z5MTW88XP815WJ7 Persistent Improvement Loop

## Overview

ATT-4845 has three immutable, scored fresh-context runs whose artifacts pass
and whose disposition is BLOCKED, but each scores only 1/3 distinct expected
decisions. Their temporary locations will disappear, and a later session
cannot safely infer which run is a baseline, whether its contents were
tampered with, or what must happen next.

**Falsifiable claim:** A future session given only the durable improvement ID
can derive one next action from retained, hash-verified evidence. The rail
will retain the minimum scored artifacts without a target export or oracle,
reject malformed/tampered/overwritten captures, and compare baseline,
candidate, and READY-control runs only after all required evidence exists.

**Non-claims:** This does not improve triage itself, rescore historical runs,
prove cross-task, cross-model, or cross-host quality, or ship any evaluation
workflow in the Recon plugin.

## Technical Design

`docs/improvement-proposals/0.22.0/requirement-closure-coverage/iteration.yaml`
is the machine-owned configuration and capture index. It has no hand-maintained
status: `tools/improvement-cycle.py state` derives state from valid retained
evidence and fixed milestone order. Authored narrative remains in the proposal
README; file hashes remain owned by each evidence manifest; HTML is a generated
view owned by the rail.

The capture subcommand accepts only a SCORED replay directory and a declared
baseline, candidate, or negative-control role. It copies exactly the receipt,
submission, result, and score into an immutable directory under `evals/evidence`;
it creates a manifest with hashes and rejects target-repository/oracle copying,
symlinks, source/result disagreement, invalid roles, tampering, and any existing
destination.

State requires three baselines, then a candidate, then one fully specified
READY control, then comparison. Its initial derived next action is therefore
to implement the generic requirement-closure candidate. The report command
renders a deterministic proposal-local HTML view and `--check` rejects byte
drift.

## Testing Strategy

The focused rail test builds isolated scored fixtures and proves capture,
derived state routing, all-role comparison, capture overwrite protection,
unscored/invalid rejection, hash tamper detection, and report byte drift.
It also asserts the operator skill runs state before any interpretation.

Run the focused rail test, replay-lab controls, generated report checks,
adapter check, links, coherence, and Decree lint/progress. Capture the three
user-named ATT-4845 scored runs using the rail before they disappear, then
render and drift-check the real proposal report.

## Acceptance Criteria

- [x] A versioned iteration record indexes only immutable, minimal, hash-verified evidence.
- [x] Capture/state/compare/report fail closed and preserve all three ATT-4845 baseline runs.
- [x] A repository-only skill starts from the state rail and emits a fresh-session handoff.
- [x] The v0.22.0 proposal and deterministic HTML distinguish authored claims, machine facts, and generated views.
- [x] Focused failure controls and complete repository validation pass.
