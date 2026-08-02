# Add recon-state: a per-ticket state canvas, derived and republished by rail

> New skill renders a node-canvas artifact per ticket; state derived from file presence, one stable URL

- **Status:** shipped (v0.13.0)
- **Shipped:** the commit tagged in v0.13.0 per [../../plans/2026-08-02-state-canvas-ledger.md](../../plans/2026-08-02-state-canvas-ledger.md)
- **Priority:** P2
- **Theme:** operational robustness
- **Origin:** 2 Aug 2026 — a session hand-built a state canvas for ATT-5047
  (approved by Doruk after two design rounds: visual node map, one-liner cards,
  all detail behind click-popovers). Every step — reading the workspace, deriving
  "stopped at the approval gate" from `discovery/gate.yaml`'s absence, filling the
  HTML, publishing — was manual judgment. Refreshing it requires a human asking a
  session that knows the context.

## Problem

"Where is this ticket in recon and what do I do next?" has no glanceable answer.
The dossier is a frozen record of a finished run; pipeline state lives only as
file presence that a human (or model) must interpret. The one canvas that exists
was authored freehand — nothing guarantees the next one derives the same state
from the same workspace, and nothing refreshes it when the run moves.

## Before (today)

The ATT-5047 canvas exists as a one-off artifact. Its state was derived by a
model reading the workspace and reasoning; regenerating it for ATT-5107 would
start from prose, not a rail. Nothing updates it when `gate.yaml` lands.

## After (proposed)

One command (or auto at every STOP/gate): skill *recon-state* runs
*derive-state.sh* `<TICKET>`, which walks a CLOSED decision table over registry
file presence + key fields and emits *state/state.yaml*:

```yaml
ticket: ATT-5047
derived: 2026-08-02T09:41:00Z
stop: approval-gate        # from the decision table; contradictions → exit 1
nodes: {workspace: done, triage: done, blocked_path: not-taken, contract: done,
        repro: done, routing: done, brief: done, approval_gate: current,
        handoff: queued, dossier: absent}
facts: {disposition: READY, route: new-spec, governance: decree,
        exhibits: 5, scenarios: 4, open: [OPEN-1]}
next: "answer the gate — resolves OPEN-1, writes discovery/gate.yaml"
```

A render rail fills the fixed canvas template (nodes, wires, glow, popovers) from
`state.yaml` + artifact fields only — every card string is templated, popover
content is extracted from `triage.yaml` / `routing.yaml` / `repro.md`, the model
authors nothing. The skill publishes to the ticket's persisted URL and logs
`canvas_published` to the [ticket-ledger](../ticket-ledger/README.md), whose
events render as the canvas timeline.

```
$ recon/scripts/derive-state.sh ATT-5047
state: approval-gate  (routing.yaml present, spec-draft.md present, gate.yaml absent)
wrote state/state.yaml
```

## Implementation sketch

- New skill *recon-state* owning stage dir *state/* — *state.yaml*,
  *canvas.html*, *artifact-url* (the stable per-ticket URL; republish targets it).
- Rails: *derive-state.sh* (decision table; unknown presence-combination → exit 1
  naming the contradiction); *render-state-canvas.sh* + template file (canvas is
  the approved ATT-5047 design: dark node canvas, elbow wires, current-node glow,
  next-action chip, popovers).
- Publish gate: FIRST publish per ticket asks in-session (creates the URL, saved
  to *state/artifact-url*); later republishes to the same URL are automatic.
  Dossiers stay frozen; the canvas is the living view — separate skills on purpose.
- Auto-refresh trigger rows in `pipeline.md`: every STOP and every gate
  presentation invokes *recon-state* (render + republish) in the stage's Report
  step; also on demand via the skill directly.
- `registry.yaml` entries for the three *state/* artifacts + mirrors;
  `plugin.json` skill entry; CLAUDE.md role lines; `docs/flow.html` gains the new
  lettered stage → republish the flow artifact (the manual mirror).
- **Depends on:** [ticket-ledger](../ticket-ledger/README.md) for the timeline
  strip; the canvas ships degraded (no timeline) without it.

## Open questions

- Artifact publishing needs a Claude session (the Artifact tool isn't a shell
  rail) — is render-always + publish-when-interactive acceptable for headless runs?
- The node set mirrors pipeline.md's state machine — worth a coherence token check,
  or is the template being versioned with the plugin enough?
- One canvas per ticket forever, or archive the artifact when a ticket closes?
