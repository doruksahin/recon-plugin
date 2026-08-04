---
date: '2026-08-04'
governs:
- tools/replay-ticket.py
- tools/test-replay-lab.sh
- tools/render-replay-lab-report.py
- tools/test-replay-lab-report.sh
- evals/README.md
- evals/skills/recon-replay-lab/SKILL.md
- evals/skills/recon-replay-lab/references/handoffs.md
- evals/skills/recon-replay-lab/references/interpretation.md
- docs/replay-lab-report.html
- docs/plans/2026-08-04-real-ticket-replay-laboratory.md
- docs/improvement-proposals/0.20.0/README.md
- docs/improvement-proposals/0.20.0/offline-valid-replay-verification/README.md
id: SPEC-01KZ63VTJ3DK28E7N5Q1F9F6N8
references:
- ADR-01KZ0ZK4WYVWRY0WJM2CZ7ZS8C
status: implemented
---

# SPEC-01KZ63VTJ3DK28E7N5Q1F9F6N8 Recon 0.20.0 Offline-Valid Replay Verification

## Overview

The immutable ATT-4845 replay at
`/private/tmp/recon-att-4845-skill.xZsdtD/run` scored FAIL because its
production triage artifact could not be made valid inside the isolated
environment: the production verifier derived `BLOCKED`, required resolved
`owner_account_id` values, and required a verbatim Jira quote. The replaying
context had neither an executable verifier nor a permitted offline identity.

**Falsifiable claim:** for a newly prepared ATT-4845 run, a correctly formed
offline submission with a configured replay-only owner identity passes the
prepared verifier; an invalid disposition, identity, or quote fails with a
stable diagnostic before handoff.

**Non-claims:** this does not improve Recon judgment, validate a model answer,
alter shipped `recon-triage` behavior, change Jira owner resolution, or prove
portability beyond the isolated controls and the next prepared ATT-4845 run.

## Technical Design

`prepare` will atomically publish a self-contained `verifier/` directory with
the current production `triage-tools.py`, an executable `verify-submission.py`
wrapper, and a replay-only owner identity map. The wrapper validates only the
prepared submission against the prepared ticket; it creates its temporary
production-shaped workspace outside the run, calls the copied production
parser/verifier, and writes nothing. Its identity map is an explicit
`replay-owner-identities.json` owner-to-token mapping. Tokens are laboratory
identities, not Jira account IDs, so the replaying LLM selects a listed value
instead of querying or guessing an account identifier.

`REPLAY.md` owns one exact command, `python3 verifier/verify-submission.py`.
It requires the replaying LLM to run that command until it exits zero before it
returns its path-only handoff. The receipt records hashes for every bundled
verifier component; state and evaluation reject verifier drift. Evaluation
uses the bundled verifier for the artifact result, preserving contract failures
as exit 2 and retained quality failures as exit 1. Decision coverage is
`NOT_EVALUATED` when artifact verification fails and may never be presented as
coverage evidence.

The scoring oracle and fixtures remain in the case directory only. Neither is
copied into a prepared run. Existing PREPARED/SUBMITTED/SCORED directories,
including the failed origin, remain immutable: prepare and evaluate retain
their no-overwrite behavior.

## Testing Strategy

The isolated control creates clean and deliberately invalid submissions. It
asserts bundled-verifier success; disposition/derived-check mismatch; missing
and invalid offline identities; paraphrased and verbatim quotes; oracle and
fixture exclusion; prepared/evaluation overwrite refusal; persisted
PREPARED→SUBMITTED→SCORED state derivation; and no decision-coverage evidence
after verifier failure. The report generator runs the same corrected control,
and its structural test asserts the updated source-derived explanation.

Run the focused replay and report controls, skill quick validation, Decree
lint/progress, adapter drift, links, and coherence. Then prepare a new
ATT-4845 run against the named frozen AdCreative repository commit and invoke
its verifier without authoring a submission in this operator context.

## Acceptance Criteria

- [x] Newly prepared runs bundle an oracle-free, production-compatible verifier and hash-pinned replay-only owner identity map.
- [x] `REPLAY.md`, the replay skill, and progressive references require the exact clean verifier command before the fresh context returns a handoff.
- [x] The bundled verifier accepts a valid offline submission and rejects disposition mismatch, missing/invalid owner identity, and paraphrased quote with stable diagnostics.
- [x] Oracle/fixture isolation, immutable prepare/evaluation behavior, and conversation-independent PREPARED→SUBMITTED→SCORED state remain proven by isolated controls.
- [x] Evaluation distinguishes verifier contract failures from retained quality failures and never treats `NOT_EVALUATED` coverage as evidence.
- [x] The generated HTML report and structural gate are regenerated from source and explain the corrected bounded workflow.
- [x] Decree, focused controls, skill validation, adapter drift, links, and coherence pass; a new ATT-4845 directory is PREPARED and its verifier is executable.
