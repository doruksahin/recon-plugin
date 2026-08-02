# Derive the disposition from the six checks

> Compute the verdict from the six checks by script; lint fails on mismatch

- **Status:** shipped (v0.9.0) — implemented 1 Aug 2026 (`recon/scripts/verify-triage.sh`
  + `triage-tools.py`, SKILL.md step 3 rewritten, pipeline.md invariant 15)
- **Priority:** P1
- **Theme:** determinism rail
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — the model wrote both the checks and
  the verdict; they happened to agree, but nothing enforces it.

## Problem

`recon-triage` SKILL.md states the disposition rule as prose:

> Disposition rule: any of checks 2–5 failing with an unanswered owner-question →
> `BLOCKED`. Only soft ambiguity (check 1 `partial`) → `NEEDS_INFO` […]

The model evaluates the six checks *and* writes `disposition:` into `triage.yaml`.
Two judgments that must be consistent are made independently, and no rail compares
them — `verify-comment-shape.sh` checks the comment's shape, not the verdict's
correctness. The verdict is the single most consequential field in the pipeline
(it decides whether discovery runs or the posting path fires).

## Before (today)

Nothing prevents this internally inconsistent `triage.yaml` from shipping:

```yaml
evidence_ok: false
design_dependency: true      # failing, with an open owner-question blocker
backend_dependency: true     # failing, with an open owner-question blocker
disposition: NEEDS_INFO      # ← prose rule says BLOCKED; no script notices
```

The wrong comment gets drafted, the wrong pipeline branch is taken, and the error
is only catchable by a human rereading the SKILL.md rule against the yaml.

## After (proposed)

The model fills in only the six check values and `blockers[]`. A script derives the
verdict and the workspace lint fails on mismatch:

```
$ bash recon/scripts/verify-triage.sh ATT-5107
disposition: FAIL — checks imply BLOCKED (evidence_ok=false + design_dependency=true
with open blocker 'Updated design'), triage.yaml says NEEDS_INFO
```

The derivation is a ~15-line pure function over the yaml:

```
blocked   = any(check in [evidence_ok=false, product_decision_open, design_dependency,
                          backend_dependency] with a matching open blocker entry)
needs_info = not blocked and outcome_decidable == partial   # blockers must be non-empty
ready      = not blocked and not needs_info
```

SKILL.md's prose rule shrinks to one line: *"Disposition is derived — run
`verify-triage.sh`; on failure fix the checks, never hand-edit the verdict."*

## Implementation sketch

- New `recon/scripts/verify-triage.sh` (or a `disposition` sub-check inside the
  validator from [validate-triage-yaml](../../0.14.0/validate-triage-yaml/README.md) — these
  two ship best as one script).
- Wire into `lint-workspace.sh` so the Report step catches it unconditionally.
- Delete the prose disposition rule from `recon-triage/SKILL.md` step 3; replace
  with the one-liner. Update pipeline.md's invariants table in the same commit.

## Open questions

- Does "failing with an unanswered owner-question" map 1:1 to "a blocker entry
  exists for that check"? Today the mapping is implicit; the script forces us to
  make it explicit (likely: each blocker gets a `check:` field naming its source).
