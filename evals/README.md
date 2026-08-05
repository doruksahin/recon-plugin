# Recon real-ticket replay laboratory

Replay one frozen task against a named plugin and target-repository commit,
then score the retained artifact. This is repository evaluation tooling; it is
not part of the shipped Recon runtime.

For private teammate review across many live dossiers, use the separate
[version-review contract](version-reviews/README.md) and
[operator skill](skills/recon-version-review/SKILL.md). That flow groups runs by
the actual published plugin version and routes accepted themes into this replay
laboratory only after sanitization; it does not store private evidence here.

For the visual explanation—both folder trees, reasoning, concrete scenarios,
before/after controls, and the complete runbook—open the generated
[Replay Laboratory Operator Report](../docs/replay-lab-report.html). Its bytes,
source hashes, line references, and embedded command outputs are checked by
repository coherence.

## Read in this order

1. This file for the operator contract and available cases.
2. [`skills/recon-replay-lab/SKILL.md`](skills/recon-replay-lab/SKILL.md) when an
   LLM starts, resumes, evaluates, compares, or explains a run.
3. One case's `case.json` for its cutoff, input, repository commit, and hash.
4. `input/` when running the replay.
5. `oracle/` only when scoring or reviewing the rubric. Never expose it to the
   replaying agent.

## LLM workflow: one run path, two contexts

The operator context prepares and explains. A fresh replay context authors and
verifies the submission. The operator resumes from retained state and
evaluates. The run directory—not the conversation—is the handoff handle.

Ask an LLM to use `$recon-replay-lab`, or follow the same commands directly.

### 1. Prepare in the operator context

```bash
python3 tools/replay-ticket.py validate evals/cases/att-4845-pre-comment
python3 tools/replay-ticket.py prepare evals/cases/att-4845-pre-comment \
  --repo /path/to/AdCreative-Frontend-V2 --out /tmp/att-4845-replay
python3 tools/replay-ticket.py state /tmp/att-4845-replay
```

The final command must derive `PREPARED` and print the next action. The operator
then gives a fresh LLM only `/tmp/att-4845-replay`, asks it to follow
`REPLAY.md`, and stops. That LLM writes only `submission/triage.yaml`, copies
only listed replay-only owner identities (never Jira account IDs), and runs:

```bash
python3 verifier/verify-submission.py
```

It corrects the submission until that command exits 0, then returns the same
run path. The bundled verifier contains no oracle or scorer fixture.

### 2. Resume in the operator context

```bash
python3 tools/replay-ticket.py state /tmp/att-4845-replay
python3 tools/replay-ticket.py evaluate /tmp/att-4845-replay
python3 tools/replay-ticket.py state /tmp/att-4845-replay
```

The states are deliberately small:

| State | Retained fact | Exact next action |
| --- | --- | --- |
| `PREPARED` | Receipt and oracle-free inputs exist; submission does not. | Hand the run to a fresh LLM and stop. |
| `SUBMITTED` | `submission/triage.yaml` exists; no evaluation exists. | Run `evaluate` once. |
| `SCORED` | Submission, `evaluation/score.txt`, and `evaluation/result.json` agree by hash. | Explain or compare the retained result; never evaluate again. |
| Exit 2 | Receipt, path, hash, or artifact combination violates the contract. | Report the diagnostic; do not guess or repair silently. |

`prepare` exports the exact target commit and never copies the case oracle.
`evaluate` first runs the prepared production-compatible verifier, assigns
independent decisions to distinct blockers with deterministic maximum matching,
and atomically retains both human and machine-readable results. Exit 1 is a
retained quality failure; exit 2 is a laboratory contract failure, including a
failed bundled verifier. That failure creates no decision-coverage evidence.

## Concrete before and after

Before these state rails, a handoff depended on chat history: the operator had
to remember the case, candidate path, scoring command, and terminal result.
Afterward, another LLM can receive only the run path, derive the stop and next
action, and recover the immutable score artifacts. This improves replay
follow-up mechanics; it does not yet prove better model judgment.

## Cases

| Case | Class | Frozen point | Current measured purpose |
| --- | --- | --- | --- |
| `att-4845-pre-comment` | ambiguous capability change | Immediately before the first human analysis comment | Audit generic decision closure against three independently calibrated blocking decisions; reject a merged audit before scoring |
| `requirement-closure-ready-control` | fully specified capability change | Frozen synthetic control on 2026-08-04 | Prove that requirement-closure hardening preserves READY when no blocking decision is open |

## Claim boundary

One case proves one evaluation rail, not general plugin quality. Fixture scores
prove the scorer's mechanics, not model behavior. A plugin improvement requires
a retained fresh-context before/after replay. General workflow claims require
at least three representative real tickets, a fixed rubric, independent review,
and all raw outputs.
