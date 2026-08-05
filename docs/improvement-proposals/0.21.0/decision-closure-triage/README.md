# Retain observable decision closure in triage

> Retain and verify generic observable-decision closure in triage.

- **Status:** shipped (v0.19.0)
- **Shipped:** [v0.19.0](https://github.com/AdCreative-ai/recon-plugin/releases/tag/v0.19.0) from [PR #2](https://github.com/AdCreative-ai/recon-plugin/pull/2), merged as [`321514d`](https://github.com/AdCreative-ai/recon-plugin/commit/321514df18e487c64ef17cbcaea974c99722e89c)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-4845 replay, 2026-08-04 — immutable run
  `/private/tmp/recon-att-4845-replay.wff6Fv/run` passed artifact verification
  as READY with zero blockers even though its frozen evaluation expected a
  blocked outcome and found no decision coverage.
- **Depends on:** offline-valid-replay-verification

## Problem

The current six checks let detailed acceptance criteria stand in for an audit
of whether observable choices are actually selected. A model can therefore
produce a syntactically valid READY artifact without retaining how it decided
that alternatives, thresholds, mapping, ownership, or fallbacks were closed.

## Before (today)

```text
artifact: PASS
actual disposition: READY
expected disposition: BLOCKED
blockers: 0
decision coverage: 0/7
```

## After (proposed)

```yaml
decision_audit:
  - id: DEC-1
    status: OPEN
    blocking: true
    check: product_decision_open
    blocker_id: BLK-1
    evidence:
      - kind: quote
        text: "Which visible outcome should occur?"
        source: description
```

The verifier rejects a missing or overloaded `BLK-N` join and derives the
dependency checks from blocking OPEN entries. CLOSED, optional, and
implementation-freedom candidates remain auditable without creating blockers.

## Implementation sketch

- Extend the canonical triage skill and fixed parser/verifier with one audit
  schema and no task-specific vocabulary.
- Add generic clean/failing fixtures, including evidence drift and a READY
  negative control, then include the rail in coherence.
- Calibrate the repository-only ATT-4845 oracle from frozen ticket/source
  evidence, update its fixtures, and regenerate the lab report.

## Open questions

None for the first persisted interface. Semantic discovery quality remains a
fresh-context replay question.
