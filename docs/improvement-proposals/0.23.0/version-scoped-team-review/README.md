# Retain version-scoped team review

> Review private Recon dossiers by the plugin version that produced them.

- **Status:** implemented; private field trial pending
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** Recon v0.19.0 rollout planning, 2026-08-05 — the team wanted to
  review reports for many Jira tickets without posting comments, but Recon had
  only per-ticket runtime workspaces and proposal-specific replay evidence.

## Problem

Arbitrary feedback cannot be placed in `$RECON_ROOT/<TICKET>/` because the
workspace registry correctly rejects unknown files. Grouping reviews by sprint
would also mix reports produced by different plugin behavior. Manual copies do
not retain the dossier hash, plugin release commit, independent reviewer
identity, consensus, or a safe boundary before a future improvement proposal.

## Before (today)

```text
~/.claude/recon/ATT-1234/report/dossier.html
teammate feedback: chat or an unrelated note
producing plugin version: not part of the review collection identity
cross-ticket synthesis: manual
```

## After (implemented)

```text
python3 tools/version-review.py state <private-root> --plugin-version 0.19.0
state: REVIEWING
runs: 8
reviews: 6
consensus: 4/8
allowed_action: add-review | add-consensus
```

All v0.19.0 reports remain under `versions/v0.19.0/`, even when a selected
theme later becomes a proposal or ships in another version. The rail rejects
Jira mutation results, source/report identity drift, unknown review references,
overwrites, premature synthesis or closure, non-Git/nested/public review roots,
origin drift, and live GitHub privacy drift.

## Implementation sketch

- Add a repository-only external-root rail, schema, semantic templates, and
  operator skill under `evals/`; nothing ships in the plugin.
- Capture only the dossier and minimal current-run artifacts; exclude raw Jira,
  delivery, ledger, and archive paths.
- Validate review → consensus → synthesis → future-proposal references and
  derive the lifecycle from retained files.
- Add focused controls, linked root/nested agent routers, and the generated
  system-map layer.
- Require a distinct private GitHub repository, pin its origin and verified
  visibility in the version cycle, recheck privacy before writes, and keep
  read-only state derivation available offline.

## Deferred field evidence

- Private synchronization is now concretely owned by
  `AdCreative-ai/recon-team-reviews`; its workflow value still requires a real
  team field trial.
- Workflow value remains unproven until at least three representative private
  ticket reports receive independent teammate review.
