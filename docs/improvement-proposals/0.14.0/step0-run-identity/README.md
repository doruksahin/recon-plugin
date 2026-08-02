# Key the step-0 guard on run identity

> Key the fresh-workspace guard on a run token, not elapsed time

- **Status:** proposed
- **Priority:** P3
- **Theme:** operational robustness
- **Origin:** ATT-5107 triage run, 1 Aug 2026 — after a mid-run credential fix, the
  second `fresh-workspace.sh` call printed `SKIPPED — step 0 already ran 371s ago`.
  Correct outcome, but only because the timer heuristic happened to align with
  reality.

## Problem

`fresh-workspace.sh` enforces "step 0 runs exactly once per run" with an
elapsed-time window. "Run" is a logical concept (one triage invocation) but the
guard measures a physical one (seconds since last stamp). The two disagree in both
directions:

- A genuinely **new** run started inside the window silently *reuses* a stale
  workspace — rule 8's fresh-workspace invariant breaks with no error.
- A **slow** run (long repro, user AFK at the gate) that re-touches step 0 outside
  the window would archive its *own in-progress artifacts* mid-flight.

The escape hatch (`RECON_STEP0_FORCE=1`) pushes the ambiguity onto the model —
"only if this is genuinely a NEW run" — which is a judgment call about exactly the
thing the script can't tell it.

## Before (1 Aug run, verbatim)

```
archived: SKIPPED — step 0 already ran 371s ago (once-per-run guard); continuing
note: only if this is genuinely a NEW run, re-invoke with RECON_STEP0_FORCE=1
```

The run had been interrupted by an expired token and resumed after the fix. Same
logical run → SKIP was right. But if the user had instead said "start over", the
same output would have been wrong, and nothing distinguishes the two cases.

## After (proposed)

Step 0 stamps a run token; subsequent script calls pass it:

```
$ bash recon/scripts/fresh-workspace.sh ATT-5107
workspace: /Users/doruk/.claude/recon/ATT-5107
run: r-20260801-a3f2                       # ← stamped into meta.yaml
archived: 3 entries -> runs/20260801-130525/
```

Every other rail (`verify-*`, `package-artifacts`, `attach-artifacts`) reads the
token from `meta.yaml` and refuses to run against a workspace whose token it wasn't
given — and `fresh-workspace.sh` called *with* the current token says "already
initialized" deterministically, with no timer:

```
$ bash recon/scripts/fresh-workspace.sh ATT-5107 --run r-20260801-a3f2
archived: SKIPPED — run r-20260801-a3f2 already initialized this workspace
$ bash recon/scripts/fresh-workspace.sh ATT-5107          # no/new token = new run
archived: 5 entries -> runs/20260801-182144/
```

The skill's step 0 carries the token through the run (it's printed once, quoted in
the progress note, passed to each script). `RECON_STEP0_FORCE` disappears.

## Implementation sketch

- `fresh-workspace.sh`: generate token (timestamp + random suffix — fine in bash;
  the no-Date restriction applies to Workflow scripts, not shell), write to
  `meta.yaml` as `run_id:`, accept `--run <token>` for the idempotent-continue case.
- Thread `run_id` assertions through the other scripts (one shared helper).
- SKILL.md rule 8 drops the timer language and the FORCE escape hatch.

## Open questions

- Does the harness re-invoking a skill after interruption reliably keep the token
  in context? (It's printed in step 0's quoted output, so yes in practice — the
  transcript is the carrier.)
