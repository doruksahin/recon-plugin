# Real-ticket replay laboratory — implementation plan

Implements [real-ticket-replay-lab](../improvement-proposals/0.19.0/real-ticket-replay-lab/README.md)
under `SPEC-01KZ5TE6QP704T8G2HJNXSP58W`.

The offline-validity follow-on is governed by
`SPEC-01KZ63VTJ3DK28E7N5Q1F9F6N8` and
[offline-valid-replay-verification](../improvement-proposals/0.20.0/offline-valid-replay-verification/README.md).

## Bounded claim

For the frozen ATT-4845 pre-comment input and target commit, the laboratory
distinguishes a production-valid six-blocker artifact that merges two decisions
from a production-valid seven-blocker artifact with atomic coverage. Success is
the scorer's retained 6/7 FAIL and 7/7 PASS outputs. This milestone does not
claim that a model or plugin revision produces the passing artifact.

## Build

- [x] Freeze and hash the sanitized ticket input at the pre-comment cutoff.
- [x] Define the separate seven-decision lexical oracle.
- [x] Implement strict case validation.
- [x] Implement atomic preparation from an immutable target-repository commit.
- [x] Reuse the production triage verifier before scoring.
- [x] Implement one-to-one decision/blocker matching and overload diagnostics.
- [x] Add atomic-pass and combined-layout-fail controls.
- [x] Add focused negative tests for input drift, oracle leakage, and overwrite.

## Demonstrate

```bash
python3 tools/replay-ticket.py validate evals/cases/att-4845-pre-comment
bash tools/test-replay-lab.sh
```

Retain the raw focused-test output. A later skill revision must add a fresh
model replay from an isolated prepared directory; fixtures are not substituted
for that live result.

## Exit and next iteration

Accept v1 when the focused controls and repository-wide checks pass. Next,
replay the current released skill in a fresh context, preserve its submission
and score, then change the skill only if the failure is reproducible. Add two
more task classes before making a general quality claim.

## Offline-validity follow-on

The immutable ATT-4845 failure was a laboratory-surface defect: the fresh
context had no executable verifier or permitted identity to satisfy the
production owner field. Preparation now bundles the production verifier
snapshot, an explicit replay-only owner map, and one pre-handoff verification
command. Focused controls prove the rail and its rejection diagnostics. The
new ATT-4845 run remains for a genuinely fresh LLM, so this is a fair-surface
claim rather than a claim of improved judgment.
