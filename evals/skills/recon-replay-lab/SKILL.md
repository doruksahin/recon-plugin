---
name: recon-replay-lab
description: Prepare, hand off, resume, evaluate, compare, and explain repository real-ticket replay runs. Use for starting or continuing a frozen Recon replay, checking a run state, scoring a returned LLM submission, or explaining replay evidence and next actions.
---

# Recon Replay Lab

Operate the repository-only replay laboratory through its deterministic rail.
Keep the oracle-aware operator context separate from the fresh LLM context that
authors the submission.

## Preserve the boundary

- Work from the `recon-plugin` repository root.
- Never author or edit `submission/triage.yaml` in the operator context.
- Never expose `evals/cases/*/oracle/` to the replaying context.
- Never contact Jira or mutate an external system during a replay.
- Treat `tools/replay-ticket.py` output and retained files as state; never infer
  progress from conversation memory.
- Treat exit 1 from `score` or `evaluate` as a retained quality failure. Treat
  exit 2 as a contract failure and stop without silently repairing the run.
- A fresh replay context must run `python3 verifier/verify-submission.py` until
  it exits zero before it returns a submission handoff. Its identity map is
  replay-only; never resolve or guess a Jira account ID.
- Never overwrite or revise a scored run. Prepare another run for the next
  attempt.

## Route from retained state

When the user provides a run directory, run:

```bash
python3 tools/replay-ticket.py state <run-dir>
```

Route only from its result:

- `PREPARED`: present the fresh-context handoff and stop.
- `SUBMITTED`: evaluate, derive `SCORED`, then explain the result.
- `SCORED`: do not evaluate again; explain the retained result.
- Exit 2: report the exact diagnostic and stop.

When no run directory exists, start a run.

## Start a run

1. Select the user-named case. If none is named and exactly one directory
   exists under `evals/cases/`, use it and say why. Otherwise ask for the case.
2. Require the target repository path containing the commit pinned in
   `case.json`. Do not guess it.
3. Use a user-provided new run path. If none is provided, create a unique
   temporary parent and use its non-existing `run` child.
4. Run the fixed sequence:

```bash
python3 tools/replay-ticket.py validate <case-dir>
python3 tools/replay-ticket.py prepare <case-dir> --repo <target-repo> --out <run-dir>
python3 tools/replay-ticket.py state <run-dir>
```

5. Require `PREPARED`. Explain the case ID, ticket, pinned target commit,
   copied skill hash, exact submission path, excluded oracle, and prohibited
   external actions from `receipt.json`, `REPLAY.md`, and rail output.
6. Read [references/handoffs.md](references/handoffs.md), render its start
   handoff with absolute paths, and stop. Do not continue into replay work.

## Resume a run

1. Run `state` before reading or changing anything.
2. For `PREPARED`, explain that no submission exists, render the start handoff
   from [references/handoffs.md](references/handoffs.md), and stop. A returned
   submission needs a clean bundled verifier result; otherwise route it back to
   the fresh context instead of evaluating it.
3. For `SUBMITTED`, run:

```bash
python3 tools/replay-ticket.py evaluate <run-dir>
python3 tools/replay-ticket.py state <run-dir>
```

4. Require `SCORED` after either evaluate exit 0 or exit 1. Never rerun
   evaluation.
5. For `SCORED`, read `evaluation/result.json` and `evaluation/score.txt`, then
   read [references/interpretation.md](references/interpretation.md). Lead with
   the observed score, decision coverage, missed decisions, and overloads.
6. Report the run path, submission hash, score hash, retained artifact paths,
   exact next action, evidence level, and non-claims. Use the resume handoff in
   [references/handoffs.md](references/handoffs.md) only when another LLM or
   session must take over.

## Compare runs

Require every run to derive `SCORED`. Compare retained `result.json` fields and
skill hashes; do not compare memory or summaries. Read both references, use the
comparison handoff, name sample count and model/host metadata if known, and
bound conclusions to the tested case and recorded contexts.
