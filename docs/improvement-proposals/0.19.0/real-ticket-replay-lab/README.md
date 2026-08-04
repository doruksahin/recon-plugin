# Build a real-ticket replay laboratory

> Replay frozen real tickets and score distinct decision coverage

- **Status:** release candidate (v0.19.0)
- **Release candidate:** [PR #2](https://github.com/doruksahin/recon-plugin/pull/2), merged as [`321514d`](https://github.com/doruksahin/recon-plugin/commit/321514df18e487c64ef17cbcaea974c99722e89c)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-4845, reviewed 4 Aug 2026 — the verified triage produced six
  blockers, while the ticket's first human analysis exposed seven independent
  decisions. Keyword presentation and intro-layout behavior were merged.

## Problem

Recon's current verifier proves schema, derived disposition, and quote parity.
It does not prove that every independent decision was found or kept atomic. A
plausible six-blocker ATT-4845 triage therefore reports `verify: clean` even
though one product decision is hidden inside another question.

Without frozen inputs and an oracle separated from the replay context, prompt
edits can only be defended with anecdotes. The team cannot rerun the same ticket
at the same repository commit or tell whether a revision improved decision
coverage, merely changed wording, or learned the expected answer.

## Before (today)

```text
$ bash recon/scripts/verify-triage.sh ATT-4845
verify: clean — disposition BLOCKED derived from checks, 6 blocker(s), 9 quote(s) verified

Human analysis decisions: 7
Recon blockers:           6
Merged: keyword presentation + intro-layout behavior
Mechanical diagnostic:   none
```

## After (proposed)

The same merged candidate remains production-valid but fails the separate lab
rubric:

```text
$ python3 tools/replay-ticket.py score evals/cases/att-4845-pre-comment candidate.yaml
artifact: PASS — production triage verifier clean
disposition: PASS — BLOCKED
decision coverage: FAIL — 6/7 distinct decisions
missed: intro-layout — Whether seeded state preserves intro layout
overloaded blocker 2: keyword-presentation, intro-layout
score: FAIL
```

Splitting those decisions produces a seven-blocker control and `score: PASS —
7/7`. The result is bounded to ATT-4845's lexical oracle; synonyms outside the
oracle remain review work.

## Implementation sketch

- Add `evals/` as a repository-only, progressive-disclosure case ledger.
- Freeze a sanitized pre-comment ATT-4845 `ticket.json` and immutable target
  commit; keep `oracle/` outside every prepared run.
- Add `tools/replay-ticket.py` with strict `validate`, atomic `prepare`, and
  production-verifier-first `score` commands.
- Score decision families with maximum one-to-one matching so one blocker
  cannot satisfy two decisions.
- Add clean seven-blocker and merged six-blocker controls plus a focused shell
  test. No SKILL.md changes land in this milestone.

## Open questions

- What stable harness API should launch fresh Claude Code and Codex sessions
  without weakening isolation? Deferred until manual prepared runs are useful.
- Which READY and NEEDS_INFO tickets should complete the first representative
  three-case set?
