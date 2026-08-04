# Iterate a Recon behavior

Use this playbook for every Recon skill proposal or revision. The unit of
iteration is a task outcome, not a prompt edit. Read the
[core principles](../principles/README.md) first.

## 1. Freeze the origin

Capture before proposing a solution:

```text
Task/run and date:
Recon version or commit:
Target repository commit and environment:
Exact start state and input:
Actual commands/actions:
Actual output artifact:
User or workflow consequence:
Durable evidence location:
```

Without a real origin and retained artifact, run a bounded spike and label it a
hypothesis. Do not open an improvement proposal.

## 2. Freeze one claim

```text
For <input and start state>,
the current result <baseline> will become <target>.
Success is observed by <artifact/command/verdict>.
The change must reject <negative control> with <diagnostic>.
This does not claim <excluded dimensions>.
```

Do not use “better,” “robust,” or “reliable” without a measure.

## 3. Fix the control surface and interface

Use the [skill spectrum](../principles/skill-spectrum.md). Record the selected
mode, freedom, trigger, inputs, outputs, side effects, failure behavior, and
verification before editing.

## 4. Build one accountable change

- Give each shared fact one owner and check its mirrors.
- Replace alternate execution paths; keep no unevidenced fallback.
- Delete prompt prose made redundant by a rail.
- Add verifier and failing fixtures with the producer.
- Verify at every changed producer/consumer boundary.
- Keep the diff atomic enough for one commit subject to name the outcome.

## 5. Demonstrate

Run the [demonstration playbook](demonstration.md). Preserve failed artifacts
before revising the mechanism.

## 6. Compare

| Dimension | Before | After | Evidence | Status |
| --- | --- | --- | --- | --- |
| Target task | artifact/verdict | artifact/verdict | durable path or ID | proven / failed / untested |
| Negative control | acceptance/diagnostic | rejection/diagnostic | raw output | proven / failed / untested |
| Repeatability | runs and variance | runs and variance | raw results | proven / failed / untested |
| Portability | hosts/models | hosts/models | per-run record | proven / failed / untested |
| Intervention | manual corrections | manual corrections | action log | proven / failed / untested |

Do not hide a failed row. It defines the next iteration.

## 7. Decide and report

- **Accept** when the bounded claim is proven.
- **Iterate** when the outcome fails but the hypothesis remains viable.
- **Reject** when evidence contradicts the mechanism or measured value.
- **Keep as experiment** when only E1 or E2 exists for a user-visible claim.

Report observed outcome, exact verification, real-task result, claim boundary,
and remaining risk before design explanation.
