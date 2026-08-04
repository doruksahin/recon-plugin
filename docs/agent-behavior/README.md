# Recon agent operating contract

> Talk is cheap. Recon improves only when a real task produces a better,
> rerunnable outcome.

Read this file before proposing or changing Recon behavior. It is the only
mandatory entry document. The runtime authority remains
[`recon/docs/pipeline.md`](../../recon/docs/pipeline.md).

## Core contract

- Start from an observed task outcome, not an imagined feature.
- Separate fact, inference, proposal, and demonstrated outcome.
- Move repeatable execution onto deterministic rails.
- Keep judgment only where meaning varies; retain the evidence behind it.
- Do not claim improvement without a rerunnable before/after demonstration.
- Bound every conclusion to the tasks, models, hosts, and failure cases tested.

## Disclosure levels

| Level | Content | Loading rule |
| --- | --- | --- |
| Entry | This contract and router | Always for behavior work |
| Task | One principle reference and/or playbook | Only when its row below matches |
| Calibration | Historical evidence audits | Only when a concrete precedent is needed |

## Route by work

Read only the rows needed for the current task.

| Current work | Read next |
| --- | --- |
| Propose or change Recon behavior | [Core principles](principles/README.md), then [Iteration playbook](playbooks/iteration.md) |
| Choose between prompt guidance, a rail, or a workflow | [Skill spectrum](principles/skill-spectrum.md) |
| Evaluate whether a claim is justified | [Evidence and claims](principles/evidence.md) |
| Build or review a test or live demo | [Demonstration playbook](playbooks/demonstration.md) |
| Calibrate against a real Recon change | [Example catalog](examples/README.md) |

The [playbook index](playbooks/README.md) explains the execution paths. Do not
read the examples unless a precedent is useful.

## Stop rule

No named and dated real-task origin means no improvement proposal. No retained,
rerunnable outcome means no improvement claim. Delivery state such as “merged”
or “shipped” does not override either rule.
