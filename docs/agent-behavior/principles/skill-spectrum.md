# Skill spectrum and freedom

Use this reference before deciding whether behavior belongs in context, prompt
instructions, a CLI rail, a workflow, or generative judgment. It adapts the
[Skill Design philosophy](https://skillshare.runkids.cc/docs/understand/philosophy/skill-design)
to Recon.

## Spectrum

Classify each behavior, not merely the whole skill.

| Mode | Use in Recon | Required control |
| --- | --- | --- |
| Passive context | Stable domain facts or conventions | One authoritative owner; load only when relevant |
| Instructional judgment | Semantic review, scenario quality, visual meaning | Narrow rubric plus cited evidence |
| CLI wrapper | Parsing, rendering, validation, mutation, fixed policy | Exact inputs, outputs, exit status, and diagnostics |
| Workflow | Ordered stages, gates, producer/consumer boundaries | Explicit state transitions and boundary verification |
| Generative work | Questions, Gherkin, explanations, briefs | Constrained inputs/output shape and real-task evaluation |

## Selection rules

1. If behavior is repeated and mechanically decidable, use a CLI rail.
2. If order or approval matters across mechanisms, use a workflow whose steps
   call rails.
3. If multiple semantic answers can be valid, retain instructional or generative
   judgment and require its source evidence.
4. If information only changes interpretation, keep it passive and load it on
   demand.
5. Move toward less model freedom as fragility, repetition, security risk, or
   failure cost rises.

Do not create a fake deterministic score for semantic truth. Determinism governs
execution; judgment remains accountable through artifacts.

## Interface-first record

Before implementation, fix:

| Decision | Required answer |
| --- | --- |
| Trigger | Exact event or condition |
| Inputs | Files, arguments, versions, environment, preconditions |
| Outputs | Artifact paths, schema, stdout/stderr, exit codes |
| Freedom | What the model may choose and may never improvise |
| Side effects | Mutations, external calls, approval boundaries |
| Failure | Fail-closed behavior, diagnostic, cleanup, retry |
| Verification | Exact command or evidence check |

Record these answers in the [iteration playbook](../playbooks/iteration.md).
