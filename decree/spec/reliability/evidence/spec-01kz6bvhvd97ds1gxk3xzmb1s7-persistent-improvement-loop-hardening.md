---
date: '2026-08-04'
governs:
- evals/skills/recon-improvement-loop/SKILL.md
- evals/README.md
- evals/cases/requirement-closure-ready-control/
- tools/replay-ticket.py
- tools/improvement-cycle.py
- tools/test-improvement-cycle.sh
- tools/CLAUDE.md
- docs/improvement-proposals/0.22.0/requirement-closure-coverage/
id: SPEC-01KZ6BVHVD97DS1GXK3XZMB1S7
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ6BVHVD97DS1GXK3XZMB1S7 Persistent Improvement Loop Hardening

## Overview

This SPEC is the immutable successor to implemented
`SPEC-01KZ69A6YY6Z5MTW88XP815WJ7`. It hardens the repository-only persistent
improvement loop before any requirement-closure candidate is implemented. The
three retained ATT-4845 baselines and their manifests remain byte-for-byte
unchanged, the raw 1/3 scorer result remains distinct from the authored 2/4
calibration, and no shipped Recon runtime, triage behavior, or ATT oracle is in
scope.

The bounded outcome is a fixed, validated experiment contract whose captures
are comparable by construction; an append-only attempt lifecycle that reaches
retained comparison and semantic review decisions; a generic report derived
from validated iteration data; and an exact candidate brief discoverable from
the state command without chat context.

## Technical Design

`iteration.yaml` owns the authored experiment contract: claim/non-claims,
target case and immutable source identities, baseline/candidate skills,
comparison rubric, negative control, learning and acceptance run thresholds,
mechanical acceptance criteria, and candidate brief path. The rail validates
the complete contract before using any evidence. Raw scorer fields remain
machine facts while authored calibration is rendered as a separately labelled
measurement with its own denominator.

Captures are append-only and attempt-scoped. The rail verifies symlink-free
sources and destinations, receipt/result/score agreement, role uniqueness,
case/ticket/commit/skill/rubric identity, disposition, artifact verdict,
overall score, and exit status. A negative control is valid only when artifact,
disposition, score, and exit status jointly prove a READY/PASS outcome.

The repository-only replay rail permits an empty required-decision rubric only
for a case whose expected disposition is READY. A frozen fully specified
control case exercises that contract; BLOCKED and NEEDS_INFO cases continue to
require at least one oracle decision. The ATT-4845 oracle is unchanged.

State derives the lifecycle
`AWAITING_CANDIDATE -> AWAITING_NEGATIVE_CONTROL -> READY_TO_COMPARE ->
AWAITING_REVIEW -> ACCEPTED | ITERATE | REJECTED`. `compare` writes a new
immutable hash-verified artifact for the current attempt. A retained review
records accept/iterate/reject plus reviewer reasoning. Accept fails closed
unless the declared mechanical matrix and acceptance run counts pass. Iterate
opens the next numbered attempt without changing any prior evidence and routes
state to its exact missing action.

The deterministic HTML renderer uses only validated contract and retained
artifacts. It renders the claim boundary, target and denominator, cases,
thresholds, every attempt, machine comparison, and explicit review decision;
it contains no ATT-specific or fixed `/4` prose. The candidate brief preserves
the generic normative-requirement audit and expected target/control outcomes,
but this change does not implement that brief.

## Testing Strategy

Extend `tools/test-improvement-cycle.sh` with isolated fixtures for every
identity mismatch, invalid READY controls, score/exit and receipt/result
disagreement, symlink leaves and ancestors, immutable comparison persistence
and tamper detection, review routing and all decision outcomes, a complete
retry attempt, non-four-denominator rendering, report drift, and byte/hash
invariance of all three retained baselines.

Run the focused improvement test, replay-lab controls and report checks,
adapter drift check, link check, coherence check, and Decree lint/progress.
Finally run real proposal state/report checks and compare frozen baseline hashes
against the pre-change snapshot.

## Acceptance Criteria

- [x] The validated iteration contract contains every declared experiment identity, threshold, acceptance criterion, and candidate brief path.
- [x] Capture rejects non-comparable candidate/control evidence, inconsistent result combinations, symlink ancestry, tampering, duplicate role misuse, and overwrite attempts.
- [x] Immutable comparisons and retained semantic decisions drive the complete terminal/retry lifecycle without overwriting prior attempts.
- [x] Accept fails closed until the declared mechanical matrix and acceptance sample thresholds pass.
- [x] The generated report is case- and denominator-generic and distinguishes scorer facts, calibration, comparison, and review decision.
- [x] State names the exact bounded candidate brief, which contains the generic target and ATT/control expected outcomes without changing shipped assets.
- [x] Focused controls cover all requested failure modes, one full retry, report drift, and unchanged retained baselines.
- [x] The complete relevant validation chain passes and all three original baseline hashes remain unchanged.
