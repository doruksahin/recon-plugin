# Requirement-closure candidate implementation brief

This is the bounded implementation handoff for the next fresh session. It is
an evaluation target, not evidence that the candidate has been implemented or
accepted.

## Scope

Implement a generic triage judgment contract that audits every normative
ticket requirement and classifies each one as exactly one of:

- closed by the ticket;
- open;
- optional;
- implementation freedom; or
- repository-resolvable.

The audit must explicitly check generic identity/mapping, ownership and update
path, threshold completeness, and ordering completeness. Every blocking open
decision must become one atomic blocker with a one-to-one audit link. Do not
introduce ATT-4845 vocabulary into any shipped asset.

## Declared target outcome

For the frozen ATT-4845 target case, the candidate is expected to retain four
separate blocking outcomes:

1. feature-context contract blocker;
2. configuration-delivery blocker;
3. broadening-threshold blocker; and
4. keyword-removal-order blocker.

The immutable historical scorer facts remain 1/3. The separate authored
calibration remains 2/4. Neither is to be rewritten or presented as the other.

## Declared negative control

Run the same candidate snapshot against the declared fully specified control
case. It must remain READY and retain artifact PASS, disposition READY/PASS,
and overall score PASS with exit 0. The control must not acquire a blocker only
because the target case is ambiguous.

## Evidence and stop boundary

Use `iteration.yaml` as the fixed experiment contract. Preserve its case,
ticket, repository, skill, rubric, threshold, and acceptance identities. After
implementation, start fresh candidate and control runs; capture them only with
`tools/improvement-cycle.py`. Do not edit retained evidence or reuse a scored
run. Stop at the state rail's next action and make no cross-task, cross-model,
or cross-host claim.
