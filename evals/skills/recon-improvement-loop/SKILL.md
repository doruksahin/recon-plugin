---
name: recon-improvement-loop
description: Resume or operate a versioned Recon plugin improvement from retained evidence. Use for plugin-improvement, improvement-resume, evidence capture, state, comparison, review, or durable handoff requests.
---

# Recon Improvement Loop

Operate repository-only plugin improvements from their durable proposal ID.
This skill is never shipped in the Recon plugin and must never infer progress
from chat memory, a temporary replay path, or an unverified summary.

## State comes first

Resolve the user's improvement ID to its proposal directory and run this before
reading an evidence file, proposing code, or explaining progress:

```bash
python3 tools/improvement-cycle.py state <proposal-dir>
```

If it exits 2, report its diagnostic and stop. Do not repair retained evidence
or invent a replacement. The command validates the fixed experiment contract,
all retained hashes, candidate/control comparability, comparisons, and reviews.
It prints one state and exactly one next action; follow only that action.

## Route from retained state

| State | Required action |
| --- | --- |
| `AWAITING_BASELINES` | Capture only the missing SCORED baseline run(s). |
| `AWAITING_CANDIDATE` | Open the printed candidate brief, implement only that bounded candidate in a fresh implementation session, then capture the requested fresh candidate run(s). Do not claim an improvement. |
| `AWAITING_NEGATIVE_CONTROL` | Capture the requested fresh run(s) of the declared fully specified READY control using the same candidate snapshot. |
| `READY_TO_COMPARE` | Run `compare`; it retains an immutable hash-verified comparison artifact. |
| `AWAITING_REVIEW` | Inspect the retained comparison and record one semantic `accept`, `iterate`, or `reject` review with reviewer reasoning. |
| `ACCEPTED` | Report the bounded accepted claim and its non-claims; do not broaden it. |
| `REJECTED` | Report the retained rejection and reasoning; do not reopen or overwrite it. |

An `ITERATE` review is retained on its attempt and state immediately opens the
next numbered attempt. Follow the new state's exact candidate action. Previous
candidate, control, comparison, and review artifacts remain immutable.

## Capture

Only capture a run the replay rail already derives as `SCORED`. Choose a new,
kebab-case evidence ID; the destination must not exist.

```bash
python3 tools/improvement-cycle.py capture <proposal-dir> \
  --role candidate --id <new-evidence-id> --from <scored-run-dir>
```

Use `baseline` and `negative-control` only when state requests those roles. The
rail enforces the declared case, ticket snapshot, repository commit, skill
binding, rubric, result consistency, role order, attempt, and no-overwrite
contract. It rejects symlink leaves and ancestors. Capture retains only the
receipt, submission, evaluation result, score, and checksum manifest; never
copy a target repository or hidden oracle.

## Compare and review

After state says `READY_TO_COMPARE`:

```bash
python3 tools/improvement-cycle.py compare <proposal-dir>
python3 tools/improvement-cycle.py report <proposal-dir>
python3 tools/improvement-cycle.py report <proposal-dir> --check
```

After state says `AWAITING_REVIEW`, retain exactly one decision:

```bash
python3 tools/improvement-cycle.py review <proposal-dir> \
  --decision <accept|iterate|reject> \
  --reviewer "<reviewer identity>" \
  --reasoning "<semantic evidence and bounded reasoning>"
```

`accept` fails closed unless the declared mechanical acceptance matrix and
acceptance run counts pass. A mechanical PASS never substitutes for semantic
review. Learning thresholds may allow an initial comparison with fewer fresh
runs than acceptance; use `iterate` to open the next numbered attempt.

## Fresh-session handoff

```text
From the recon-plugin root, read evals/skills/recon-improvement-loop/SKILL.md
and run: python3 tools/improvement-cycle.py state <proposal-dir>. Follow only
the printed next_action and its candidate brief. Do not use temporary runs,
modify retained evidence, rewrite scorer/calibration facts, or claim
cross-task/model/host quality.
```
