---
description: Render a ticket's living state canvas — a node-map artifact showing where the recon run stands and what to do next — derived mechanically from the workspace and republished to one stable per-ticket URL. Use when asked where a ticket stands, for a recon status/state page, or invoked by other recon skills at a STOP or gate to refresh the canvas.
---

# Recon State

One glanceable node canvas per ticket: every pipeline stage as a card, the current stop glowing with a next-action chip, the ticket's event history as a timeline. The state is DERIVED from artifact presence by a rail — the workspace *is* the state — and the canvas republishes to the same private artifact URL for the ticket's whole life.

## Contract

- **Input:** ticket ID (precondition: a run exists — root `meta.yaml`)
- **Reads:** current-run artifacts + `history.ndjson` (timeline VIEW only — invariant 16), the shipped `template.html`
- **Writes:** ONLY inside `~/.claude/recon/<TICKET>/state/` — `state.yaml`, `canvas.html`, `artifact-url`
- **External side effects:** publishes/republishes `state/canvas.html` as a **private** artifact. FIRST publish for a ticket is gated in-session; republishes to the saved URL are not. Never posts to Jira, never touches the repo.

---

## ⚠️ CRITICAL: Rules

1. **The rails decide everything.** `derive-state.sh` derives the state (a contradiction exits 1 — report it verbatim as a workspace/plugin bug and STOP; never hand-derive around it). `render-state-canvas.sh` fills the template. You author NOTHING in the canvas — no extra facts, no reworded status text.
2. **One stable URL per ticket.** `state/artifact-url` holds it. If present: republish to it (pass it as the artifact `url`), no questions. If absent: ask ONCE — `Publish a private state canvas for <TICKET>? (creates its stable URL)` with options `Publish` / `Not now` — on Publish save the returned URL to `state/artifact-url` (the file is exactly one line: the URL); on Not now stop after rendering (the canvas stays on disk).
3. **Living view, frozen dossier.** The canvas ALWAYS shows the present and is republished freely; it never replaces the dossier, and dossiers are never retro-updated. Do not merge the two.
4. **NEVER read `runs/`** (invariant 3). The timeline comes from `history.ndjson` only — and only as rendered output, never as an input to any judgment (invariant 16).
5. **Keep artifact identity stable:** title `<TICKET> — Recon State`, favicon `🧭` — same on every republish.

---

## Workflow

1. **Derive** — `bash "<skill base dir>/../../scripts/derive-state.sh" <TICKET>`. Exit 2 → no run: tell the user to run `/recon:recon-triage <TICKET>` first and stop. Exit 1 → quote the contradiction line and stop.
2. **Render** — `bash "<skill base dir>/../../scripts/render-state-canvas.sh" <TICKET>` → `state/canvas.html`.
3. **Lint** — `bash "<skill base dir>/../../scripts/lint-workspace.sh" <TICKET>`; fix any violation.
4. **Publish** per rule 2 (load a prerequisite skill first if the environment requires one, e.g. `artifact-design`). Description: one sentence naming the ticket and its stop.
5. **Log** — after a successful publish: `bash "<skill base dir>/../../scripts/log-event.sh" <TICKET> canvas_published` (invariant 16).

## Report

```
State: <derive-state.sh first output line, verbatim>
Rendered: ~/.claude/recon/<TICKET>/state/canvas.html
Lint: <lint-workspace.sh verdict line, verbatim>
Published: <URL> (stable for this ticket) | render-only (your choice) | first publish declined
Next: <the `next:` line from state/state.yaml, verbatim>
```

---

## Reference

- Auto-refresh: other recon skills invoke this skill at a STOP or gate presentation **only when `state/artifact-url` already exists** (trigger table in `../../docs/pipeline.md`) — creating the canvas is always a user act, so the first-publish gate never fires unattended.
- Whole-chain spec (stages, invariants, artifact registry, trigger table): `../../docs/pipeline.md` relative to this skill's base directory. On conflict, this SKILL.md wins.
