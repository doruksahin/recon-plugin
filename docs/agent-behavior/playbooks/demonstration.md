# Demonstrate an outcome

Use this playbook to test or review a claim. Select admissible language from
[evidence and claim boundaries](../principles/evidence.md).

## Rerunnable demonstration packet

Retain:

```text
Purpose and claim under test
Exact version/commit
Isolated or resettable start state
Exact commands or numbered human actions
Expected output and exit status
Observed raw output and artifact paths
Targeted failing case and expected diagnostic
Cleanup/reset instructions
```

No hidden correction is allowed. Record every human or agent intervention as
part of the result.

## Live demonstration

A live demo uses a named real task on the real surface. Record the action
sequence and retain resulting logs, screenshots, video, state, or mutation
response. Run before and after from an equivalent start state.

Mocks establish rail properties. A narrated walkthrough, code diff, mock-only
run, or green static check does not establish a user-visible outcome.

## Minimum evidence by claim

| Claim | Minimum evidence |
| --- | --- |
| Parser, renderer, verifier, mutation rail | One clean fixture plus every bounded failure class; assert exit and diagnostic |
| Workflow order or gate semantics | Clean end-to-end path plus fault injection at every changed boundary; inspect persisted state |
| Task-specific user-visible outcome | One named, recorded real task |
| General workflow outcome | Three representative real tasks |
| Skill activation or routing | Three positive and three adjacent negative prompts per named model tier, each in fresh context |
| Generative output quality | Three representative real tasks, fixed rubric, independent evaluation, all raw outputs |
| Host or harness portability | Same demo on every host or harness named, including degraded behavior |
| Speed, cost, context reduction | Same-workload measurements with sample count and variance |

Choose representative task classes from the claimed surface—for example happy
path, ambiguous/needs-information, and blocked/failure. A finite matrix supports
only the named classes; it never proves “works for any task.”

Higher-risk changes require more cases. When evidence cannot meet the row, lower
the claim rather than the threshold.
