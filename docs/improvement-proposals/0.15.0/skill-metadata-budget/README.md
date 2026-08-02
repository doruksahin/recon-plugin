# Enforce a skill metadata budget

> Keep every skill description under 200 characters and fail checks on overflow

- **Status:** shipped (v0.15.0) — companion improvement, not standalone proof
  of better activation
- **Priority:** P2
- **Theme:** determinism rail
- **Origin:** The 2 Aug 2026 skill-design audit measured seven of eight Recon
  descriptions above the recommended 200-character activation budget.

## Problem

Skill descriptions are always-loaded routing metadata. In v0.14.1, Recon spent
2,166 characters across eight descriptions; only `recon-triage` was under 200.
The longest descriptions mixed output behavior, host degradation, trigger phrases,
and internal sequencing. That increased shared-context cost and made activation
boundaries harder for smaller models to distinguish.

This was not merely prose cleanup: metadata decides which company workflow loads.

## Before (v0.14.1)

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

No generator or coherence check rejected the overflow.

## After (implemented)

```text
$ python3 tools/generate-adapters.py --check
adapters: clean — 10 generated file(s)

measured: 8/8 descriptions 177–195 chars
total: 1,477 chars (−689, −31.8%)
gate: non-empty · unique · ≤200 · Use when / Invoked by cue
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

Implemented under
*SPEC-01KZ14Q6A2WB6J6TTX3XWQC5QJ Recon 0.15.0 Verified Handoff Chain*.

## Decision note

- Character count remains a proxy. This was included only as a small companion to
  outcome work; periodically cross-model smoke-test false-positive/false-
  negative activation before claiming routing improvement.
