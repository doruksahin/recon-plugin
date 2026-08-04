# Generic decision-closure triage

**Origin:** The immutable ATT-4845 replay on 2026-08-04 was syntactically
valid but recorded `READY`, zero blockers, and zero evaluated decisions.

## Interface

`triage/triage.yaml` gains a mandatory `decision_audit` list. It retains one
generic ID, closure status, check, blocking flag, typed evidence, and—only for
a blocking open choice—the corresponding atomic blocker ID. The associated
blocker repeats both its own ID and the decision ID, making the join auditable
in either direction.

## Boundaries

The skill judges what candidates exist and whether an observable result is
closed. The verifier checks only schema, sources, file lines, one-to-one joins,
check agreement, and derived disposition. It will not claim to calculate
semantic completeness.

## Demonstration

Focused synthetic controls prove rail mechanics. ATT-4845 remains the single
real-task fresh-context calibration: its oracle is separately reviewed from
the frozen input and target source, then the updated skill is handed to a new
prepared context. No improvement claim is made before that returned artifact
is evaluated.
