# Make prepared replays production-valid without Jira

> Make prepared replays production-valid without Jira

- **Status:** shipped (v0.19.0)
- **Shipped:** [v0.19.0](https://github.com/AdCreative-ai/recon-plugin/releases/tag/v0.19.0) from [PR #2](https://github.com/AdCreative-ai/recon-plugin/pull/2), merged as [`321514d`](https://github.com/AdCreative-ai/recon-plugin/commit/321514df18e487c64ef17cbcaea974c99722e89c)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-4845 replay, 2026-08-04 — immutable run
  `/private/tmp/recon-att-4845-skill.xZsdtD/run` failed artifact verification:
  `BLOCKED` was derived while `NEEDS_INFO` was submitted, an owner account ID
  was absent, and the Jira quote was paraphrased.
- **Depends on:** real-ticket-replay-lab

## Problem

The original prepared directory asked a fresh LLM to follow the production
triage skill but withheld Jira. Production requires a resolved
`owner_account_id`; the isolated environment gave no safe alternative and
provided no executable pre-handoff verifier. The run was therefore unable to
produce a fair production-valid artifact without guessing or breaking replay
isolation.

## Before (today)

```text
artifact: FAIL — production triage verifier exited 1
VERIFY: disposition: checks derive BLOCKED … triage.yaml says NEEDS_INFO
VERIFY: blocker 1: owner_account_id missing or malformed — resolve it … never guess
VERIFY: evidence … quote not found verbatim in description
score: FAIL
decision coverage: NOT_EVALUATED
```

## After (proposed)

```text
$ python3 verifier/verify-submission.py
verify: clean — disposition BLOCKED derived from checks, 7 blocker(s), 1 quote(s) verified
replay verifier: clean — 7 replay-only owner identity value(s) verified
```

The supplied `replay-owner-identities.json` maps each permitted owner to an
explicit laboratory token. Any absent, unknown, or Jira-shaped account value
fails before handoff. The oracle and scorer fixture content remain absent.

## Implementation sketch

- Extend `tools/replay-ticket.py` preparation and receipt validation with a
  hash-pinned verifier bundle and replay owner map.
- Reuse copied production `triage-tools.py` from an executable wrapper; retain
  evaluation and state semantics while adding verifier fault controls.
- Require the exact verifier command in `REPLAY.md` and the replay skill's
  fresh-context handoff, then update its interpretation reference.
- Regenerate the source-derived HTML operator report and assert its changed
  workflow contract.

## Open questions

None for the bounded offline rail. Whether an LLM produces a good ATT-4845
triage remains a subsequent measured question.
