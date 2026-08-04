# Evidence and claim boundaries

Use this reference when evaluating a proposal, test result, demo, or handoff.

## Classify the statement first

| Statement class | Meaning |
| --- | --- |
| Fact | Directly observed in a retained source or artifact |
| Inference | Explanation derived from facts but not directly observed |
| Proposal | Intended mechanism or expected result |
| Outcome | Result produced by executing the changed behavior |

Do not let a sentence silently move between classes.

## Evidence ladder

Claims may not rise above their evidence.

| Level | Evidence | Permitted language |
| --- | --- | --- |
| E0 | Opinion or preference | “idea,” “question” |
| E1 | Static analysis, code reading, or proposed before/after | “hypothesis,” “expected” |
| E2 | Rerunnable fixtures, negative cases, and captured diagnostics | “the rail enforces…” |
| E3 | Recorded run on a named real task with retained artifacts | “on task X, the outcome changed…” |
| E4 | Independent tasks across every dimension named in the claim | “works across the tested tasks/models/hosts…” |

`shipped`, `merged`, and `checks pass` describe delivery state. They do not raise
the evidence level.

## Claim rules

- One successful task proves only that task.
- Fixtures prove bounded mechanism properties, not user-visible outcomes.
- A summary without a durable evidence location remains E1 even if it describes
  a real event.
- Cross-model, cross-host, portability, speed, and cost claims each require
  evidence from that dimension.
- Record explicit non-claims beside the target claim.
- Lower the claim when evidence is narrow. Never lower the evidence threshold
  after seeing a failure.

Use the [demonstration playbook](../playbooks/demonstration.md) to produce E2–E4
evidence and the [recorded repro audit](../examples/recorded-repro-runtime.md) to
see these boundaries applied.
