# Core principles

Read this file when proposing, changing, or evaluating Recon behavior. Use the
linked leaves only when their decision surface becomes relevant.

## Outcome before solution

1. Begin with an observed ticket, run, fixture, or failure. Record its date,
   versions, exact input, actual output, and consequence.
2. Keep observed fact, inference, proposal, and demonstrated outcome distinct.
   A plausible diagnosis is not a fact; a merged change is not proof.
3. Write one falsifiable claim before designing the fix. Define success, a
   negative control, and explicit non-claims.

## Mechanism before instruction

4. Move parsing, ordering, rendering, mutation, schemas, and bounded policy onto
   rails. Keep semantic or visual judgment in the model only with visible
   evidence.
5. Design trigger, inputs, outputs, side effects, failure behavior, and
   verification before prompt prose. Prefer one safe default.
6. Remove superseded prose and alternate execution paths when a rail lands.

Use [skill-spectrum.md](skill-spectrum.md) to choose the control surface.

## Evidence before confidence

7. Demonstrate the same scenario before and after from an equivalent start
   state. Retain commands, outputs, logs, screenshots, or video.
8. Test failure deliberately. Assert the exit status and intended diagnostic,
   not merely that something failed.
9. Bound the conclusion to the task classes, models, hosts, and failure cases
   exercised. State what remains untested.

Use [evidence.md](evidence.md) to select admissible claim language.

## Neutral core, explicit extensions

10. Express core behavior through observable inputs, states, and outputs rather
    than one team's vocabulary or one task shape. Quarantine governance-specific
    behavior in its adapter.
11. Never claim “any task” from a finite test set. Name the tested task classes
    and keep extension points explicit.
12. Report artifacts and outcomes before design explanation or effort.

## Admissible improvement checklist

Do not claim an improvement until its record contains a named real-task origin,
frozen baseline, falsifiable claim, control-surface choice, fixed interface,
positive and negative verification, rerun steps, outcome comparison, claim
boundary, and remaining risks. Produce that record with the
[iteration playbook](../playbooks/iteration.md).
