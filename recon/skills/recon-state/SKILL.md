---
name: recon-state
description: Render a ticket's current Recon stage, stop, next action, and history as a living state canvas. Use when asked where a ticket stands, for a state/status page, or at a Recon STOP or gate.
---

# Recon State

One glanceable node canvas per ticket: every pipeline stage as a card, the current stop glowing with a next-action chip, the ticket's event history as a timeline. The state is DERIVED from artifact presence by a rail — the workspace *is* the state. A host with `publish_stable_url` may keep one private artifact URL current for the ticket's whole life; other hosts return the local canvas.

## Host setup

Before the first path or tool action, read `../../docs/hosts.md`, then run
`reconctl.sh start base` once. Retain its root, host, surface, capabilities, and
preflight snapshot for the run. A failed preflight is a hard STOP. Use
`publish_stable_url` only when declared available; otherwise keep the canvas
render-only and never write `state/artifact-url`. Later rails still detect their
current host and surface independently.

## Contract

- **Input:** ticket ID (precondition: a run exists — root `meta.yaml`)
- **Reads:** current-run artifacts + `history.ndjson` (timeline VIEW only — invariant 16), the shipped `template.html`
- **Writes:** ONLY inside `$RECON_ROOT/<TICKET>/state/` — `state.yaml`, `canvas.html`, `artifact-url`, `publish-gate.yaml` (written by the `record-publish-gate.sh` rail, never by hand)
- **External side effects:** when `publish_stable_url` is available, publishes/republishes `state/canvas.html` as a **private** artifact. The first publish is gated in-session; republishes to the saved URL are not. Without that capability the skill is render-only. Never posts to Jira or touches the repo.

---

## ⚠️ CRITICAL: Rules

1. **The rails decide everything.** `derive-state.sh` derives the state (a contradiction exits 1 — report it verbatim as a workspace/plugin bug and STOP; never hand-derive around it). `render-state-canvas.sh` fills the template. You author NOTHING in the canvas — no extra facts, no reworded status text.
2. **One stable URL only on capable hosts, and the publish answer is on the record.** Walk this table — it is mechanical, and `find` decides each row (never a guess about what a previous session did):

   | `publish_stable_url` | `state/artifact-url` | last `outcome` in `state/publish-gate.yaml` | do |
   |---|---|---|---|
   | unavailable | — | — | render and stop; NEVER create, update, or use `state/artifact-url`, NEVER ask, NEVER write `publish-gate.yaml` |
   | available | present | — | republish to that URL, no question |
   | available | absent | no record | ask ONCE, presenting `record-publish-gate.sh <TICKET> question` word-for-word |
   | available | absent | `declined` | do NOT silently re-ask: report the recorded decline and its date, and ask again only if the user's own request this session is to publish |

   Every answer is recorded before anything else happens — `bash "<skill base dir>/../../scripts/record-publish-gate.sh" <TICKET> answer <published|declined> "<the user's exact words>"`. On Publish, publish, then save the returned URL as exactly one line in `state/artifact-url`. On Not now, stop after rendering. NEVER retype the question and NEVER leave an answer unrecorded: an absent `artifact-url` must never again mean three different things at once.
3. **Living view, frozen dossier.** The canvas ALWAYS shows the present. It may be republished freely only when `publish_stable_url` is available; it never replaces the dossier, and dossiers are never retro-updated. Do not merge the two.
4. **NEVER read `runs/`** (invariant 3). The timeline comes from `history.ndjson` only — and only as rendered output, never as an input to any judgment (invariant 16).
5. **Keep artifact identity stable:** title `<TICKET> — Recon State`, favicon `🧭` — same on every republish.

---

## Workflow

1. **Derive** — `bash "<skill base dir>/../../scripts/derive-state.sh" <TICKET>`. Exit 2 → no run: quote its host-rendered Triage instruction and stop. Exit 1 → quote the contradiction line and stop.
2. **Render** — `bash "<skill base dir>/../../scripts/render-state-canvas.sh" <TICKET>` → `state/canvas.html`.
3. **Lint** — `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>`; fix any violation.
4. **Publish when available** per rule 2's table — question and answer both through `record-publish-gate.sh`. Otherwise report render-only. Description: one sentence naming the ticket and its stop.
5. **Log** — only after a successful publish: `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> canvas_published` (invariant 16).

## Report

```
State: <derive-state.sh first output line, verbatim>
Rendered: $RECON_ROOT/<TICKET>/state/canvas.html
Lint: <lint-workspace.sh verdict line, verbatim>
Published: <URL> (stable for this ticket) | render-only (capability unavailable) | first publish declined <date from publish-gate.yaml> (not re-asked)
Next: <the `next:` line from state/state.yaml, verbatim>
```

---

## Reference

- Auto-refresh: other recon skills may invoke this skill at a STOP or gate when `state/artifact-url` exists. A host without `publish_stable_url` refreshes only the local render and leaves the saved URL untouched. Because those callers only invoke on an existing URL, a refresh never reaches the publish question at all.
- The publish record is per-run, like `state/artifact-url` itself: step 0 archives `state/` wholesale, so a new run starts from "never asked" again.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
