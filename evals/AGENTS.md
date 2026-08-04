# Evals agent guide

This tree is a repository-only laboratory. Nothing under `evals/` ships in the
Recon plugin. Work from the repository root and treat retained files—not chat
history—as state.

## Route the task

- Preparing, resuming, scoring, or explaining one replay: read the
  [replay-lab skill](skills/recon-replay-lab/SKILL.md).
- Capturing evidence, comparing attempts, or recording an improvement decision:
  read the [improvement-loop skill](skills/recon-improvement-loop/SKILL.md).
- Collecting private dossiers, teammate reviews, consensus, or cross-ticket
  themes for one published plugin version: read the
  [version-review skill](skills/recon-version-review/SKILL.md) and the linked
  [external-tree contract](version-reviews/README.md).
- For the full model, commands, cases, and claim boundary, read the
  [lab README](README.md) or the generated
  [operator report](../docs/replay-lab-report.html).

Always run the applicable `state` command first and follow only its printed
next action. Never overwrite a scored run or retained evidence.

## Real examples

**Replay boundary.** The operator prepares a run from the
[ambiguous ATT case](cases/att-4845-pre-comment/case.json), then gives only the
prepared run directory to a fresh author. The author writes
`submission/triage.yaml`; the operator later evaluates it exactly once. Never
expose the case's `oracle/` directory to the author.

**Negative control.** Run the same candidate snapshot against the
[fully specified READY case](cases/requirement-closure-ready-control/case.json).
The purpose is to catch false blockers: stricter auditing is useful only if a
complete ticket remains `READY`.

**Retain failures.** This
[attempt-1 result](evidence/requirement-closure-coverage/att-4845-requirement-closure-attempt-1/evaluation/result.json)
passed the production artifact and disposition checks but covered only 2/3
decisions. It is valid evidence, not something to repair or delete. Capture and
review failed outcomes so the next attempt is based on observed behavior rather
than cherry-picked successes.

**Team-review cycle.** Initialize `versions/v0.19.0/` in a private external
root, capture one immutable minimal dossier per ticket/run, then collect
reviewer YAML against each retained report hash. The
[schema](version-reviews/schema.yaml) owns fields and enums; the
[rail](../tools/version-review.py) owns identities, indexes, hashes, and state.
Sprint membership may be discussed in feedback, but never owns the folder.

## Hard boundaries

- Replay authors read only the prepared run directory.
- Operators never author or edit a replay submission.
- Exit 1 from evaluation is a retained quality failure; exit 2 is a contract
  failure that must be reported without silent repair.
- Never copy a target repository or scoring oracle into retained evidence.
- Never commit a live version-review root, raw Jira source, or private dossier
  under `evals/`; only the generic schema, templates, skills, and controls live
  here.
- One replay supports only a task-specific claim; it does not prove general
  model, host, or plugin quality.
