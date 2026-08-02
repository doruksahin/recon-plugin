# Keep a cross-run event ledger per ticket — output, never evidence

> Append-only *history.ndjson* survives step 0; a rail logs each transition; nothing may read it as evidence

- **Status:** proposed
- **Priority:** P2
- **Theme:** determinism rail
- **Origin:** 2 Aug 2026 — building the ATT-5047 state canvas by hand. The workspace showed *where* the run stood (gate pending) but not *when or how* it got there; ATT-5107's earlier BLOCKED story was invisible because `runs/` is unreadable (invariant 3). The ticket's history had to be reconstructed from Jira comments and file mtimes.

## Problem

The pipeline is deliberately snapshot-only: the workspace **is** the state, and prior
runs are archived into `runs/`, which nothing may read. That is correct for
determinism (invariant 11) — but it destroys the ticket's *story*. Questions
teammates actually ask — "when did this go BLOCKED?", "did anyone answer the
comment?", "how many runs did this take?" — have no mechanical answer today. Any
timeline shown to humans (dossier, state canvas) is either absent or reconstructed
by a model reading Jira, which is judgment where a rail should be.

## Before (today)

Reconstructing ATT-5047's history this session meant:

```
$ ls ~/.claude/recon/ATT-5047/runs/        # forbidden to read (invariant 3)
$ stat -f '%Sm %N' triage/triage.yaml      # mtime ≈ when triage finished, maybe
2 Aug 07:31 triage/triage.yaml
```

…plus fetching Jira comments and inferring the rest. No record says when routing
ran, when the gate was presented, or that a prior run ever existed.

## After (proposed)

A root-level *history.ndjson*, preserved by `fresh-workspace.sh` across runs
(everything else still archives), written ONLY by a new rail:

```
$ cat ~/.claude/recon/ATT-5047/history.ndjson
{"ts":"2026-08-01T14:02:11Z","run":"2026-08-01T14:02:11Z","v":"0.8.0","event":"run_started"}
{"ts":"2026-08-01T14:09:40Z","run":"2026-08-01T14:02:11Z","v":"0.8.0","event":"verdict","disposition":"NEEDS_INFO","blockers":1}
{"ts":"2026-08-01T14:15:22Z","run":"2026-08-01T14:02:11Z","v":"0.8.0","event":"comment_posted","comment":"2186001","action":"created"}
{"ts":"2026-08-02T07:25:01Z","run":"2026-08-02T07:25:01Z","v":"0.9.0","event":"run_started"}
{"ts":"2026-08-02T07:31:48Z","run":"2026-08-02T07:25:01Z","v":"0.9.0","event":"verdict","disposition":"READY","blockers":0}
{"ts":"2026-08-02T08:04:19Z","run":"2026-08-02T07:25:01Z","v":"0.9.0","event":"routed","route":"new-spec"}
```

```
$ recon/scripts/log-event.sh ATT-5047 made_up_event
log-event: unknown event 'made_up_event' — allowed: run_started verdict routed
comment_posted attachments_replaced gate_answered handoff_printed dossier_published
canvas_published            [exit 1]
```

The event vocabulary is a CLOSED set; the ledger is timeline data for humans and
views — and **output, never evidence**, exactly like marker comments (invariant 4):
no check, verdict, or routing may cite it, so invariant 11 is untouched.

## Implementation sketch

- New rail *log-event.sh* `<TICKET> <event> [k=v…]` — validates event against the
  closed vocabulary, stamps ts/run/version, appends one JSON line. Unknown event or
  malformed pair → exit 1.
- `fresh-workspace.sh`: exclude *history.ndjson* from archiving; append
  `run_started` itself.
- Trigger table rows in `pipeline.md` (mechanical — which step logs what):
  step 0 → `run_started`; triage verify-clean → `verdict`; routing producer →
  `routed`; posting path → `comment_posted`, `attachments_replaced`; discovery
  gate write → `gate_answered`; step 8 → `handoff_printed`; recon-report →
  `dossier_published`.
- New invariant ("the ledger is output, not evidence"): nothing reads
  *history.ndjson* for any decision; `lint-workspace.sh` validates it parses and
  every event is in-vocabulary.
- `registry.yaml` entry (producer *log-event.sh*, consumers: state canvas, humans)
  + the three mirror docs; SKILL.md Report steps name their log calls.
- Ships with [state-canvas-skill](../state-canvas-skill/README.md)'s timeline, but
  is independently useful (a `doctor.sh`-style history dump).

## Open questions

- Should `gate_answered` record the OPEN-scenario resolutions inline, or only point
  at `gate.yaml`? (Leaning: point — one owner per fact.)
- Cap/rotation for pathological tickets? (Leaning: none; tens of lines in practice.)
