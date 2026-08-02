# Enforce a skill metadata budget

> Keep every skill description under 200 characters and fail checks on overflow

- **Status:** in-progress — accepted only as a low-risk companion to artifact
  verification, not as standalone proof of better activation
- **Priority:** P2
- **Theme:** determinism rail
- **Origin:** The 2 Aug 2026 skill-design audit measured seven of eight Recon
  descriptions above the recommended 200-character activation budget.

## Problem

Skill descriptions are always-loaded routing metadata. Recon currently spends
2,166 characters across eight descriptions; only `recon-triage` is under 200.
The longest descriptions mix output behavior, host degradation, trigger phrases,
and internal sequencing. That increases shared-context cost and makes activation
boundaries harder for smaller models to distinguish.

This is not merely prose cleanup: metadata decides which company workflow loads.

## Before (today)

```text
recon-triage      196 chars
recon-decree      243
recon-discovery   258
recon-help        240
recon-repro       290
recon-state       291
recon-publish     323
recon-report      325
result: 7/8 over budget · total 2,166 chars
```

No generator or coherence check rejects the overflow.

## After (proposed)

```text
$ python3 tools/generate-adapters.py --check
metadata: clean — 8/8 descriptions ≤200 chars
descriptions: unique · non-empty · concrete trigger language present
total: ≤1,600 chars (at least −26%)
adapters: clean — 10 generated files
```

Each description follows one form: outcome first, then concrete trigger; internal
workflow detail remains in the skill body.

## Implementation sketch

- Rewrite all descriptions to ≤200 characters without losing distinguishing
  trigger terms or internal-only warnings.
- Make adapter generation fail on length overflow, missing `Use when`, or duplicate
  descriptions.
- Preserve positive/negative routing prompts for adjacent skills as manual
  cross-model review cases; do not report them as mechanically passed activation
  tests because this repository has no model router.
- Regenerate native adapter metadata.

## Open questions

- Character count is a proxy. Ship this only as a small companion to outcome
  work, and periodically cross-model smoke-test false-positive/false-negative
  activation before claiming routing improvement.
